# ClienteFlow

Dashboard para acompanhar clientes, projetos e pagamentos. Usa Supabase para autenticação e persistência dos dados.

## Configuração

1. Crie um projeto em [Supabase](https://supabase.com/dashboard).
2. No SQL Editor, execute todo o conteúdo de `supabase/schema.sql`.
3. Depois execute `supabase/portfolio-features.sql` no mesmo editor para habilitar projetos, pagamentos, relatórios, equipe e plano Pro fictício.
4. Copie `.env.example` para `.env` e preencha a URL e a chave anon do projeto.
4. Em **Authentication > Providers > Email**, habilite o provedor de e-mail. Para desenvolvimento, desabilite a confirmação de e-mail se quiser entrar logo após criar a conta.
5. Execute `npm run dev`.

O primeiro cadastro cria automaticamente uma organização e torna o usuário administrador dela. As políticas RLS impedem acesso aos dados de outras organizações.

## Comandos

- `npm run dev`: inicia o ambiente local.
- `npm run build`: gera a versão de produção.

## GitHub Pages

O deploy é automático a cada envio para a branch `main`. Antes do primeiro deploy, no repositório do GitHub abra **Settings > Secrets and variables > Actions** e crie os secrets abaixo com os valores do seu `.env` local:

- `VITE_SUPABASE_URL`
- `VITE_SUPABASE_ANON_KEY`

Em **Settings > Pages**, escolha **GitHub Actions** como fonte de publicação. A aplicação ficará disponível em `https://prodyug.github.io/mini-saas/` após a execução do workflow.
