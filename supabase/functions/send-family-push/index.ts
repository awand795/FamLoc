import { GoogleAuth } from "npm:google-auth-library@9.15.1";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return json({ error: "Unauthorized" }, 401);

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  // Nama secret bawaan Supabase saat ini berupa peta JSON; fallback menjaga
  // kompatibilitas dengan proyek lama yang masih memakai ANON/SERVICE_ROLE_KEY.
  const publishableKeys = JSON.parse(Deno.env.get("SUPABASE_PUBLISHABLE_KEYS") ?? "{}");
  const secretKeys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}");
  const publishableKey = publishableKeys.default ?? Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = secretKeys.default ?? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!publishableKey || !serviceKey) throw new Error("Supabase function keys are unavailable");
  const callerClient = createClient(supabaseUrl, publishableKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: { user }, error: userError } = await callerClient.auth.getUser();
  if (userError || !user) return json({ error: "Unauthorized" }, 401);

  const payload = await req.json();
  const kind = String(payload.kind ?? "general");
  const title = String(payload.title ?? "FamLoc");
  const body = String(payload.body ?? "");
  const targetUserId = payload.target_user_id ? String(payload.target_user_id) : null;
  const admin = createClient(supabaseUrl, serviceKey);

  let recipientIds: string[];
  if (targetUserId) {
    const { data: relation } = await admin
      .from("friendships")
      .select("id")
      .or(`and(user_id_a.eq.${user.id},user_id_b.eq.${targetUserId}),and(user_id_a.eq.${targetUserId},user_id_b.eq.${user.id})`)
      .maybeSingle();
    if (!relation) return json({ error: "Target bukan anggota keluarga" }, 403);
    recipientIds = [targetUserId];
  } else {
    const { data: friendships, error } = await admin
      .from("friendships")
      .select("user_id_a,user_id_b")
      .or(`user_id_a.eq.${user.id},user_id_b.eq.${user.id}`);
    if (error) throw error;
    recipientIds = (friendships ?? []).map((f) => f.user_id_a === user.id ? f.user_id_b : f.user_id_a);
  }
  if (recipientIds.length === 0) return json({ sent: 0 });

  const { data: devices, error: deviceError } = await admin
    .from("device_tokens")
    .select("token")
    .in("user_id", recipientIds);
  if (deviceError) throw deviceError;

  const serviceAccountText = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON");
  if (!serviceAccountText) return json({ error: "Firebase belum dikonfigurasi" }, 503);
  const serviceAccount = JSON.parse(serviceAccountText);
  const googleAuth = new GoogleAuth({
    credentials: serviceAccount,
    scopes: ["https://www.googleapis.com/auth/firebase.messaging"],
  });
  const accessToken = await googleAuth.getAccessToken();
  const endpoint = `https://fcm.googleapis.com/v1/projects/${serviceAccount.project_id}/messages:send`;

  const results = await Promise.all((devices ?? []).map(async ({ token }) => {
    const response = await fetch(endpoint, {
      method: "POST",
      headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        message: {
          token,
          notification: { title, body },
          data: { kind, title, body },
          android: { priority: "high", notification: { channel_id: kind === "sos" ? "famloc_sos" : "famloc_checkin" } },
        },
      }),
    });
    return response.ok;
  }));
  return json({ sent: results.filter(Boolean).length });
});

function json(value: unknown, status = 200) {
  return new Response(JSON.stringify(value), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
