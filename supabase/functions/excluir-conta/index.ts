// Matutar Games · Edge Function "excluir-conta" (projeto matutar-teste).
// Apaga a conta de quem chama: o usuário do login e, em cascata, perfil, resultados e códigos.
// É a única parte que usa a chave de serviço, e ela fica só aqui no servidor (variável do Supabase).
import { createClient } from 'npm:@supabase/supabase-js@2.45.4';

// só as prévias dos sites da Matutar podem chamar (projeto de teste)
const ORIGENS = /^https:\/\/deploy-preview-\d+--(matutar-games|qualopreco|duelo-matutar|confia-matutar)\.netlify\.app$/;

function cabecalhos(origem: string | null): Record<string, string> {
  const h: Record<string, string> = { 'Content-Type': 'application/json', Vary: 'Origin' };
  if (origem && ORIGENS.test(origem)) {
    h['Access-Control-Allow-Origin'] = origem;
    h['Access-Control-Allow-Headers'] = 'authorization, apikey, content-type, x-client-info';
    h['Access-Control-Allow-Methods'] = 'POST, OPTIONS';
  }
  return h;
}
const resposta = (corpo: unknown, status: number, origem: string | null) =>
  new Response(JSON.stringify(corpo), { status, headers: cabecalhos(origem) });

Deno.serve(async (req) => {
  const origem = req.headers.get('Origin');
  if (req.method === 'OPTIONS') return new Response(null, { status: origem && ORIGENS.test(origem) ? 204 : 403, headers: cabecalhos(origem) });
  if (req.method !== 'POST') return resposta({ erro: 'metodo' }, 405, origem);
  if (!origem || !ORIGENS.test(origem)) return resposta({ erro: 'origem_nao_permitida' }, 403, origem);

  const token = (req.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '');
  if (!token) return resposta({ erro: 'sem_sessao' }, 401, origem);

  let corpo: { confirmacao?: string } = {};
  try { corpo = await req.json(); } catch { /* corpo vazio */ }
  if (corpo.confirmacao !== 'EXCLUIR') return resposta({ erro: 'confirmacao' }, 400, origem);

  const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  // quem está pedindo: sai do token da própria pessoa, nunca de um id enviado pelo navegador
  const { data, error } = await admin.auth.getUser(token);
  if (error || !data?.user) return resposta({ erro: 'sem_sessao' }, 401, origem);

  const { error: falha } = await admin.auth.admin.deleteUser(data.user.id);
  if (falha) return resposta({ erro: 'falhou' }, 500, origem);
  return resposta({ ok: true }, 200, origem);
});
