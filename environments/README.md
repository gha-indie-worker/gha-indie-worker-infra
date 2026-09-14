# Terraform environment roots

`preview`, `staging`, and `production` are isolated Terraform roots for **gha-indie-worker**. Provider-native Cloudflare, Neon, and Supabase configuration remains canonical under `modules/`; these roots compose account/environment resources without duplicating native source.

Cloudflare Worker shell creation defaults off until a concrete deployable is wired. Initialize R2 state with `terraform init -backend-config=../backend.r2.hcl.example -backend-config="key=gha-indie-worker/<environment>/terraform.tfstate"`. Keep R2 credentials and `CLOUDFLARE_API_TOKEN` outside git.
