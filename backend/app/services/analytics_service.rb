class AnalyticsService
  include ApiResponseHandler

  def self.dashboard(params)
    new.dashboard(params)
  end

  def self.report_csv(params)
    new.report_csv(params)
  end

  def self.report_pdf(params)
    new.report_pdf(params)
  end

  def dashboard(params)
    period = (params[:period] || 'month').to_s
    date_from, date_to = normalize_range(period, parse_date(params[:date_from]), parse_date(params[:date_to]))

    sales_series = sales_monthly_series(date_from, date_to)
    subs_series = subscriptions_growth_series(date_from, date_to)
    leads_dist = leads_distribution_by_source(date_from, date_to)

    top_products = compute_top_products(date_from, date_to, params)
    lead_conv = compute_lead_conversion_by_channel(date_from, date_to, params)
    metrics = compute_metrics_summary(date_from, date_to)
    kpis = compute_kpis_realtime

    payload = {
      sales_monthly: sales_series,
      subscriptions_growth: subs_series,
      leads_distribution: leads_dist,
      top_products: top_products,
      lead_conversion_by_channel: lead_conv,
      metrics_summary: metrics,
      kpis_realtime: kpis,
      sales_breakdown: sales_breakdown,
      leads_summary: leads_summary,
      transactions_count: transactions_count(date_from, date_to),
      kpis_changes: compute_kpis_changes(date_from, date_to),
      conversion_rates: conversion_rates(date_from, date_to)
    }

    success_response(payload, 200)
  rescue StandardError => e
    internal_error_response(e.message)
  end

  def report_csv(params)
    data = dashboard(params)[:data]
    csv = build_csv(data)
    success_response({ content_type: 'text/csv', filename: "dashboard_report_#{Time.current.to_i}.csv", body: csv }, 200)
  rescue StandardError => e
    internal_error_response(e.message)
  end

  def report_pdf(params)
    data = dashboard(params)[:data]
    pdf = "Dashboard Report\nTotal Vendas: #{data[:kpis_realtime][:total_sales]}\nAssinaturas: #{data[:subscriptions_growth][:values].last}" 
    success_response({ content_type: 'application/pdf', filename: "dashboard_report_#{Time.current.to_i}.pdf", body: pdf }, 200)
  rescue StandardError => e
    internal_error_response(e.message)
  end

  private

  def parse_date(val)
    return nil if val.blank?
    Time.zone.parse(val.to_s) rescue nil
  end

  def normalize_range(period, date_from, date_to)
    to = date_to || Time.current
    from = date_from || begin
      case period
      when 'day' then to.beginning_of_day
      when 'week' then (to - 7.days)
      when 'month' then to.beginning_of_month
      when 'quarter' then (to - 3.months)
      when 'year' then to.beginning_of_year
      else (to - 30.days)
      end
    end
    [from, to]
  end

  def scoped_relation(relation, from, to)
    relation.where(created_at: from..to)
  end

  def sales_monthly_series(date_from, date_to)
    purchases = scoped_relation(Purchase.all, date_from, date_to)
    subs = scoped_relation(Subscription.all, date_from, date_to)
    buckets = Hash.new(0.0)
    (purchases + subs).each do |r|
      key = r.created_at.strftime('%Y-%m')
      buckets[key] += (r.respond_to?(:value) ? r.value.to_f : 0.0)
    end
    labels = months_range(date_from, date_to)
    values = labels.map { |k| (buckets[k] || 0.0).round(2) }
    { labels: labels, values: values }
  end

  def subscriptions_growth_series(date_from, date_to)
    subs = scoped_relation(Subscription.all.order(:created_at), date_from, date_to)
    count_by_month = Hash.new(0)
    subs.each do |s|
      key = s.created_at.strftime('%Y-%m')
      count_by_month[key] += 1
    end
    labels = months_range(date_from, date_to)
    cumulative = []
    total = 0
    labels.each do |k|
      total += count_by_month[k]
      cumulative << total
    end
    { labels: labels, values: cumulative }
  end

  def leads_distribution_by_source(date_from, date_to)
    counts = scoped_relation(Lead.all, date_from, date_to).group(:source_type).count
    total = counts.values.sum.nonzero? || 1
    distribution = counts.map { |src, c| { label: src, value: c, percent: (c.to_f / total.to_f).round(4) } }
    { labels: distribution.map { |d| d[:label] }, values: distribution.map { |d| d[:value] }, details: distribution }
  end

  def compute_top_products(date_from, date_to, params)
    purchases = scoped_relation(Purchase.all, date_from, date_to).group(:plan_name).sum(:value)
    items = purchases.map { |name, amount| { name: name, amount: amount.to_f } }
    ranked = items.sort_by { |i| -i[:amount] }.each_with_index.map { |i, idx| i.merge(rank: idx + 1, volume: i[:amount]) }
    ranked
  end

  def compute_lead_conversion_by_channel(date_from, date_to, params)
    total_by_src = scoped_relation(Lead.all, date_from, date_to).group(:source_type).count
    converted_by_src = scoped_relation(Lead.where(current_stage: 'closing'), date_from, date_to).group(:source_type).count
    channels = total_by_src.keys | converted_by_src.keys
    channels.map do |ch|
      total = total_by_src[ch].to_i
      conv = converted_by_src[ch].to_i
      rate = total.zero? ? 0.0 : (conv.to_f / total.to_f)
      { channel: ch, leads: total, converted: conv, rate: rate.round(4) }
    end.sort_by { |r| -r[:rate] }
  end

  def compute_metrics_summary(date_from, date_to)
    charges = scoped_relation(Purchase.all, date_from, date_to).sum(:value).to_f + scoped_relation(Subscription.all, date_from, date_to).sum(:value).to_f
    leads_total = scoped_relation(Lead.all, date_from, date_to).count.to_f.nonzero? || 1.0
    cac = (charges.zero? ? 0.0 : (charges / leads_total)).round(2)
    ltv = (scoped_relation(Subscription.all, date_from, date_to).average(:value) || 0.0).to_f * 12
    retention_rate = (scoped_relation(Subscription.where(status: 'ACTIVE'), date_from, date_to).count.to_f / (scoped_relation(Subscription.all, date_from, date_to).count.nonzero? || 1)).round(4)
    arpu = (charges / (scoped_relation(Subscription.all, date_from, date_to).count.nonzero? || 1)).round(2)
    { cac: cac, ltv: ltv.round(2), retention_rate: retention_rate, arpu: arpu }
  end

  def compute_kpis_realtime
    total_sales = Purchase.sum(:value).to_f + Subscription.sum(:value).to_f
    new_subscriptions = Subscription.where('created_at >= ?', 24.hours.ago).count
    leads_converted = Lead.where(current_stage: 'closing').where('updated_at >= ?', 24.hours.ago).count
    { total_sales: total_sales.round(2), new_subscriptions: new_subscriptions, leads_converted: leads_converted }
  end

  def sales_breakdown
    {
      one_time: {
        count: Purchase.count,
        amount: Purchase.sum(:value).to_f.round(2)
      },
      subscription: {
        count: Subscription.count,
        amount: Subscription.sum(:value).to_f.round(2)
      }
    }
  end

  def leads_summary
    {
      total: Lead.count,
      by_stage: {
        discovery: Lead.where(current_stage: 'discovery').count,
        enchantment: Lead.where(current_stage: 'enchantment').count,
        closing: Lead.where(current_stage: 'closing').count
      }
    }
  end

  def transactions_count(date_from, date_to)
    scoped_relation(Purchase.all, date_from, date_to).count + scoped_relation(Subscription.all, date_from, date_to).count
  end

  def compute_kpis_changes(date_from, date_to)
    # Calcula percentuais de variação entre o período atual e o período imediatamente anterior
    duration = (date_to - date_from)
    prev_from = date_from - duration
    prev_to = date_from

    current_sales = scoped_relation(Purchase.all, date_from, date_to).sum(:value).to_f + scoped_relation(Subscription.all, date_from, date_to).sum(:value).to_f
    prev_sales = scoped_relation(Purchase.all, prev_from, prev_to).sum(:value).to_f + scoped_relation(Subscription.all, prev_from, prev_to).sum(:value).to_f

    current_subs = scoped_relation(Subscription.all, date_from, date_to).count
    prev_subs = scoped_relation(Subscription.all, prev_from, prev_to).count

    current_leads_conv = scoped_relation(Lead.where(current_stage: 'closing'), date_from, date_to).count
    prev_leads_conv = scoped_relation(Lead.where(current_stage: 'closing'), prev_from, prev_to).count

    current_tx = transactions_count(date_from, date_to)
    prev_tx = transactions_count(prev_from, prev_to)

    {
      total_sales_change_pct: pct_change(current_sales, prev_sales),
      subscriptions_change_pct: pct_change(current_subs, prev_subs),
      leads_converted_change_pct: pct_change(current_leads_conv, prev_leads_conv),
      transactions_change_pct: pct_change(current_tx, prev_tx)
    }
  end

  def pct_change(current, previous)
    return 0.0 if previous.to_f <= 0.0
    (((current.to_f - previous.to_f) / previous.to_f) * 100.0).round(2)
  end

  def months_range(date_from, date_to)
    start_date = date_from.to_date.beginning_of_month
    end_date = date_to.to_date.beginning_of_month
    months = []
    d = start_date
    while d <= end_date
      months << d.strftime('%Y-%m')
      d = d.next_month
    end
    months
  end

  def conversion_rates(date_from, date_to)
    leads_total = scoped_relation(Lead.all, date_from, date_to).count.to_f
    purchases_done = scoped_relation(Purchase.where(status: 'DONE'), date_from, date_to).count.to_f
    subscriptions_new = scoped_relation(Subscription.all, date_from, date_to).count.to_f
    purchases_pct = leads_total > 0 ? ((purchases_done / leads_total) * 100.0) : 0.0
    subscriptions_pct = leads_total > 0 ? ((subscriptions_new / leads_total) * 100.0) : 0.0
    {
      purchases_pct: [[purchases_pct.round(2), 0.0].max, 100.0].min,
      subscriptions_pct: [[subscriptions_pct.round(2), 0.0].max, 100.0].min
    }
  end

  def build_csv(data)
    lines = []
    lines << 'Section;Label;Value'
    data[:sales_monthly][:labels].each_with_index do |lab, idx|
      lines << "Sales Monthly;#{lab};#{data[:sales_monthly][:values][idx]}"
    end
    data[:subscriptions_growth][:labels].each_with_index do |lab, idx|
      lines << "Subscriptions Growth;#{lab};#{data[:subscriptions_growth][:values][idx]}"
    end
    data[:leads_distribution][:details].each do |d|
      lines << "Leads Distribution;#{d[:label]};#{d[:value]}"
    end
    data[:top_products].each do |p|
      lines << "Top Products;#{p[:name]};#{p[:amount]}"
    end
    data[:lead_conversion_by_channel].each do |c|
      lines << "Lead Conversion;#{c[:channel]};#{c[:rate]}"
    end
    lines << "Metrics;CAC;#{data[:metrics_summary][:cac]}"
    lines << "Metrics;LTV;#{data[:metrics_summary][:ltv]}"
    lines << "Metrics;Retention;#{data[:metrics_summary][:retention_rate]}"
    lines << "Metrics;ARPU;#{data[:metrics_summary][:arpu]}"
    lines.join("\n")
  end
end
