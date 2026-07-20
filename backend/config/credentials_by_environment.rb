# frozen_string_literal: true

class CredentialsByEnvironment
  def initialize
    load_development_credentials unless Rails.env.production?

    proxy_to_encrypted_credentials
  end

  private

  def load_development_credentials
    return unless File.exist?(path)

    hash = HashWithIndifferentAccess.new(YAML.safe_load(File.open(path)))

    hash.each do |k, v|
      self.class.send :define_method, k.downcase do
        v
      end
    end
  end

  def proxy_to_encrypted_credentials
    self.class.send :define_method, :method_missing do |m, *_a, &_b|
      Rails.application.credentials.send(m)
    end
  end

  def path
    File.join(Rails.root, 'config', "#{Rails.env}_credentials.yml")
  end
end
