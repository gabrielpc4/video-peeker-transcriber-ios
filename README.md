# VideoPeeker iOS

App iOS do VideoPeeker para importar links/áudios, enviar para o backend e acompanhar transcrição/resumo/breakdown.

## O que o app faz

- Importa mídia compartilhada via Share Extension.
- Permite usar link do clipboard (YouTube, Instagram, etc.).
- Mostra status do backend e logs locais no app.
- Exibe detalhes por item (transcrição, resumo e breakdown).
- Inclui fluxo para atualizar cookies do YouTube direto no iPhone (via sessão web isolada).

## Requisitos

- Xcode 15+
- iOS 17+ (device ou simulador)
- Backend do projeto rodando e acessível em rede

Backend separado: [videopeeker-backend](https://github.com/gabrielpc4/videopeeker-backend)

## Rodando localmente

1. Abra `VideoPeeker.xcodeproj` no Xcode.
2. Selecione o target `VideoPeeker`.
3. Rode no simulador ou device.

## Configuração de backend

- URL padrão no app:
  - `https://videopeeker-backend.onrender.com`
- Para usar backend local em device físico:
  - abra `Settings` no app
  - ajuste `Base URL` para o IP da sua máquina na mesma rede (ex.: `http://192.168.0.10:8000`)

Também existe suporte por variáveis de ambiente (útil em Schemes):

- `VIDEOPEEKER_BACKEND_BASE_URL`
- `VIDEOPEEKER_FORCE_BACKEND_BASE_URL` (`1` ou `true`)

## Estrutura

- `VideoPeeker/`: app principal (SwiftUI + SwiftData)
- `VideoPeekerShareExtension/`: extensão de compartilhamento
- `VideoPeeker.xcodeproj/`: projeto Xcode

## Observações

- O app depende do backend para processamento.
- Alguns logs ruidosos de sistema iOS podem aparecer no console (RTI/keyboard/reporter) sem impacto funcional.
