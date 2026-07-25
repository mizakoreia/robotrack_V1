# Spec — `commissioning-report` (adapt — G3)

O Protocolo de Comissionamento é o artefato que se assina. Hoje é legível no desktop e na
impressão A4, mas cortado no celular do gestor.

## ADDED Requirements

### Requirement: O documento do Protocolo é legível em viewport estreita

O sistema SHALL exibir o documento do relatório de forma legível em 375px e 320px de
largura — sem corte à direita e sem perder o carimbo, a distribuição por símbolo+rótulo e
as contagens — sem regredir o contrato de impressão A4.

*Porquê: o documento é uma tabela de 433px cravados; em 375/320px ele é cortado sem scroll
horizontal, e o gestor no celular não lê "Pendente 5" (aparece só "○ Per").*

#### Scenario: sem corte em 375px e 320px

- **WHEN** o relatório é aberto em uma viewport de 375px (e de 320px)
- **THEN** todo o conteúdo do documento é alcançável (reflow ou container com rolagem horizontal)
- **AND** o carimbo, os rótulos de status e as contagens ficam legíveis
- **AND** a saída de impressão A4 (thead/tfoot correntes, blocos indivisíveis, monocromático) permanece inalterada

### Requirement: O nome da métrica é tão legível quanto o número

O sistema SHALL apresentar o nome da métrica do carimbo com peso e cor de corpo
(`.label-md` + `text-text-main`), e SHALL NÃO usar `text-text-muted/70` (< 4,5:1) para o
nome da métrica na tela.

*Porquê: no único documento que se assina, o nome que desambigua a métrica (D15) não pode
ser menos legível que o percentual — e o carimbo hero-métrica é um ban do DESIGN.*

#### Scenario: o nome da métrica passa o contraste de corpo

- **WHEN** o carimbo e as barras do relatório são renderizados na tela
- **THEN** o nome da métrica usa `text-text-main` (sem `/70`)
- **AND** tem peso/tamanho de rótulo legível ao lado do número
