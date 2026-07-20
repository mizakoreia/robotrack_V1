import { Button } from '@/components/ui/Button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/Card'
import { downloadBuild } from '@/lib/api/downloads'
import { Download, ExternalLink, BookOpen } from 'lucide-react'
import { toast } from 'sonner'

export function SetupPage() {
  const handleDownload = async () => {
    try {
      toast.info('Iniciando download...')
      await downloadBuild()
      toast.success('Download iniciado!')
    } catch (error) {
      console.error(error)
      toast.error('Erro ao baixar o build. Verifique se o arquivo está disponível.')
    }
  }

  return (
    <div className="space-y-6">
      <div>
        <h2 className="text-3xl font-bold tracking-tight">Setup do Ambiente</h2>
        <p className="text-muted-foreground">
          Configure seu ambiente de desenvolvimento e produção com os recursos abaixo.
        </p>
      </div>

      <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
        {/* Card Comunidade Discord */}
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <ExternalLink className="h-5 w-5 text-indigo-500" />
              Comunidade Discord
            </CardTitle>
            <CardDescription>
              Junte-se à comunidade do Goat para tirar dúvidas e networking.
            </CardDescription>
          </CardHeader>
          <CardContent>
            <Button variant="uiverse" className="w-full px-3.5 py-1.5 text-[0.875rem] h-10" onClick={() => window.open('https://discord.gg/placeholder', '_blank')}>
              <span className="inline-flex items-center justify-center gap-2">
                <ExternalLink className="w-4 h-4" />
                ACESSAR DISCORD
              </span>
            </Button>
          </CardContent>
        </Card>

        {/* Card Download Build */}
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <Download className="h-5 w-5 text-emerald-500" />
              Download Build
            </CardTitle>
            <CardDescription>
              Baixe o código fonte compilado da aplicação (arquivo .zip).
            </CardDescription>
          </CardHeader>
          <CardContent>
            <Button variant="uiverse" className="w-full px-3.5 py-1.5 text-[0.875rem] h-10" onClick={handleDownload}>
              <span className="inline-flex items-center justify-center gap-2">
                <Download className="w-4 h-4" />
                MUNDO BACKEND & FRONTEND (.ZIP)
              </span>
            </Button>
          </CardContent>
        </Card>

        {/* Card Instruções */}
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <BookOpen className="h-5 w-5 text-amber-500" />
              Guia de Instalação
            </CardTitle>
            <CardDescription>
              Acesse o passo a passo completo para rodar o projeto.
            </CardDescription>
          </CardHeader>
          <CardContent>
            <Button variant="uiverse" className="btn-neutral w-full px-3.5 py-1.5 text-[0.875rem] h-10" onClick={() => window.open('/build', '_blank')}>
              <span className="inline-flex items-center justify-center gap-2">
                <BookOpen className="w-4 h-4" />
                VER INSTRUÇÕES (/BUILD)
              </span>
            </Button>
          </CardContent>
        </Card>
      </div>

      {/* Seção Passo a Passo (Prévia) */}
      <Card className="mt-6">
        <CardHeader>
          <CardTitle>Instalação Rápida</CardTitle>
          <CardDescription>Resumo dos comandos principais</CardDescription>
        </CardHeader>
        <CardContent>
          <div className="bg-muted p-4 rounded-md font-mono text-sm overflow-x-auto">
            <p className="text-muted-foreground mb-2"># 1. Descompacte o arquivo baixado</p>
            <p className="mb-4">unzip app-build.zip</p>
            
            <p className="text-muted-foreground mb-2"># 2. Configure as variáveis de ambiente</p>
            <p className="mb-4">cp .env.example .env</p>

            <p className="text-muted-foreground mb-2"># 3. Suba os containers</p>
            <p>docker-compose up -d</p>
          </div>
        </CardContent>
      </Card>
    </div>
  )
}
