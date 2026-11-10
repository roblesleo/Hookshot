# Hookshot com AMD FSR e menu em português

Este fork do [Hookshot](https://github.com/NotRexed/Hookshot) traz três novidades:

- **AMD FSR 4 e FSR 3.1** no menu de upscaling, ao lado do DLSS. Funciona em qualquer placa de vídeo.
- **Menu do F1 em 13 idiomas**, português incluído, com a opção de idioma do menu e do jogo.
- **Uma janela de montagem**, o mini-builder, que monta o jogo a partir da sua cópia sem usar linha de comando.

O resto é o Hookshot original. Todo o crédito do port é do projeto Hookshot.

> **O jogo não está aqui e nunca vai estar.** Você precisa da sua própria cópia de *The Legend of Zelda: Ocarina of
> Time* para Switch 2 (programa `0400486024DEC000`, atualização v131072). Nunca compartilhe a pasta do jogo montado: ela
> contém o jogo.

## Como montar

1. **Instale o Hookshot Builder oficial** e abra-o uma vez: ele baixa as ferramentas de compilação que o mini-builder
   usa. Baixe em [github.com/NotRexed/Hookshot/releases/latest](https://github.com/NotRexed/Hookshot/releases/latest).
   Não precisa montar o jogo por ele.
2. **Baixe este código:**
   [github.com/roblesleo/Hookshot/archive/refs/heads/fsr.zip](https://github.com/roblesleo/Hookshot/archive/refs/heads/fsr.zip).
   Extraia o arquivo.
3. Abra a pasta **`fsr-builder`** e dê dois cliques em **`Montar-Hookshot-FSR.bat`**.
4. Na janela que abre:
   - **Seu jogo:** escolha o arquivo `.nup`. A janela procura sozinha em Downloads, Área de Trabalho e Documentos.
   - **Instalar o jogo em:** a pasta onde o jogo vai ficar.
   - **Idioma do jogo:** um dos 16 idiomas.
   - **NVIDIA DLSS também:** marque só se tiver placa NVIDIA RTX. A licença da NVIDIA aparece para você aceitar.
5. Clique em **Montar o jogo**. Leva de 20 a 45 minutos e precisa de uns 60 GB livres. No fim, clique em **Jogar**.

Se o Windows bloquear os arquivos baixados, clique com o botão direito no `.bat` e no `.ps1`, abra
**Propriedades** e marque **Desbloquear**.

A janela baixa sozinha as DLLs do FSR do GitHub oficial da AMD, e as do DLSS do GitHub da NVIDIA quando você marca o
DLSS. Ela confere cada arquivo pelo hash.

## As opções novas do menu (F1)

**Aba Gráficos:**

| Opção | O que faz |
|---|---|
| **Upscaler** | Escolhe quem amplia a imagem 3D. **Do jogo** usa o upscaler do próprio jogo. **AMD FSR** amplia de uma resolução menor. **AMD FSR Native AA** deixa o 3D em resolução cheia e só suaviza as bordas. **NVIDIA DLSS** e **NVIDIA DLAA** só aparecem em placas RTX montadas com DLSS. |
| **Versão do FSR** | **Auto** usa a escolha da AMD: FSR 4 em Radeon RX 9000, 7000, 6000 e APUs Ryzen recentes, e FSR 3.1 nas outras placas. **FSR 4** e **FSR 3.1** forçam uma versão. |
| **Modelo FSR 4** | Aparece com a versão FSR 4. **Auto** usa o modelo da AMD, ou o INT8 Lite nas placas em que a AMD não oferece FSR 4 (NVIDIA e Intel). Também dá para forçar **FP8** (para RX 9000), **INT8** (RX 7000), **INT8 RDNA2** (RX 6000) ou **INT8 Lite** (portáteis e APUs). |
| **Resolução interna** | Com FSR ou DLSS: Auto, Qualidade (67%), Equilibrado (58%), Desempenho (50%) e Ultra Desempenho (33%). |
| **Nitidez** | Com FSR ou DLSS, a imagem fica mais suave que a do jogo. Uns 80% costumam ficar bons. |

**Aba Jogo:**

| Opção | O que faz |
|---|---|
| **Idioma do jogo** | O idioma dos textos do jogo. Grava o `language.txt` e vale depois de reiniciar. |
| **Idioma do menu** | **Auto** segue o idioma do jogo. Também dá para escolher um de 13 idiomas: inglês, português, espanhol (América Latina e Espanha), francês, alemão, italiano, holandês, polonês, russo, japonês, coreano e chinês (simplificado e tradicional). |

### Qual FSR usar?

- **Placa AMD Radeon RX 6000, 7000 ou 9000, ou portáteis AMD como o Legion Go e o ROG Ally:** Versão do FSR em Auto.
  A AMD escolhe o melhor FSR 4 para a sua placa.
- **Placa NVIDIA RTX:** o DLSS costuma ficar melhor e mais leve. Se quiser testar o FSR 4, use o modelo INT8 Lite. O
  FSR 3.1 é o mais leve.
- **Placa NVIDIA GTX ou Intel:** FSR 3.1, ou FSR 4 com o modelo INT8 Lite, se a placa aguentar.

## Problemas

O arquivo `hookshot_log.txt` na pasta do jogo diz qual FSR rodou. Procure as linhas que começam com `vk: AMD FSR`.
Ele não contém nada do jogo, então pode ser compartilhado para pedir ajuda.

## Créditos

- O [Hookshot](https://github.com/NotRexed/Hookshot) e todos os seus colaboradores.
- AMD, pelo FSR SDK. O runtime é baixado do GitHub oficial da AMD, sob a licença da AMD.
- [OptiScaler](https://github.com/optiscaler/OptiScaler), pela documentação dos modelos do FSR 4. Nenhum código dele
  foi copiado.
- Feito com a ajuda do Claude (Anthropic).
