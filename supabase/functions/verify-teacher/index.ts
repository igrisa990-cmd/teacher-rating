import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { ...cors, "Content-Type": "application/json" },
});

const normalize = (value: string) => value.toLocaleLowerCase("ru-RU")
  .replace(/ё/g, "е").replace(/[^а-яa-z0-9]+/gi, " ").trim();

const safeOfficialUrl = (value?: string | null) => {
  if (!value) return null;
  try {
    const url = new URL(value);
    const host = url.hostname.toLowerCase();
    if (url.protocol !== "https:" || host === "localhost" || host.endsWith(".local") ||
      /^(127\.|10\.|0\.|169\.254\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.)/.test(host) ||
      /^\[?::1\]?$/.test(host)) return null;
    return url;
  } catch { return null; }
};

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (request.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const authHeader = request.headers.get("Authorization") || "";
  const userClient = createClient(supabaseUrl, anonKey, { global: { headers: { Authorization: authHeader } } });
  const admin = createClient(supabaseUrl, serviceKey);
  const { data: auth } = await userClient.auth.getUser();
  if (!auth.user) return json({ error: "unauthorized" }, 401);

  const { request_id } = await request.json();
  if (!request_id) return json({ error: "request_id_required" }, 400);
  const { data: item, error } = await admin.from("teacher_requests").select("*").eq("id", request_id).single();
  if (error || !item) return json({ error: "request_not_found" }, 404);
  if (item.user_id !== auth.user.id) return json({ error: "forbidden" }, 403);

  const finish = async (outcome: string, method: string, confidence: number, evidence: Record<string, unknown>) => {
    const { data, error: rpcError } = await admin.rpc("finalize_teacher_verification", {
      p_request_id: request_id, p_outcome: outcome, p_method: method,
      p_confidence: confidence, p_evidence: evidence,
    });
    if (rpcError) throw rpcError;
    return json({ outcome, method, confidence, teacher_id: data });
  };

  // 1. Уже существующий учитель в выбранной школе — наиболее надёжное совпадение.
  if (item.school_id) {
    const { data: teachers } = await admin.from("teachers").select("id,name,subject")
      .eq("school_id", item.school_id);
    const exact = teachers?.find((teacher) => normalize(teacher.name) === normalize(item.teacher_name) &&
      normalize(teacher.subject) === normalize(item.subject));
    if (exact) return await finish("verified", "internal_database", 1, { matched_teacher_id: exact.id });
  }

  // 2. Используем только URL, уже сохранённый у школы как официальный. Пользовательский URL
  // без подтверждённой школы не запрашиваем, чтобы не превращать функцию в SSRF-прокси.
  let officialUrl: URL | null = null;
  if (item.school_id) {
    const { data: school } = await admin.from("schools").select("source_url").eq("id", item.school_id).single();
    officialUrl = safeOfficialUrl(school?.source_url);
  }
  if (officialUrl) {
    try {
      const response = await fetch(officialUrl, {
        headers: { "User-Agent": "TeacherPlusVerifier/1.0" }, signal: AbortSignal.timeout(7000),
      });
      const length = Number(response.headers.get("content-length") || 0);
      if (response.ok && length < 2_000_000) {
        const page = normalize((await response.text()).slice(0, 2_000_000));
        const nameParts = normalize(item.teacher_name).split(" ").filter((part: string) => part.length > 1);
        const nameFound = nameParts.length >= 2 && nameParts.every((part: string) => page.includes(part));
        const subjectFound = page.includes(normalize(item.subject));
        if (nameFound && subjectFound) return await finish("verified", "official_school_page", .94, { source_url: officialUrl.origin });
      }
    } catch { /* Недоступный сайт не является основанием для отказа. */ }
  }

  // 3. Необязательный адаптер внешнего реестра. Endpoint и токен хранятся только в secrets.
  const registryEndpoint = Deno.env.get("TEACHER_REGISTRY_ENDPOINT");
  const registryToken = Deno.env.get("TEACHER_REGISTRY_TOKEN");
  if (registryEndpoint && registryToken) {
    try {
      const response = await fetch(registryEndpoint, {
        method: "POST", headers: { "Content-Type": "application/json", Authorization: `Bearer ${registryToken}` },
        body: JSON.stringify({ name: item.teacher_name, subject: item.subject, school: item.school_name, city: item.city, region: item.region }),
        signal: AbortSignal.timeout(7000),
      });
      if (response.ok) {
        const result = await response.json();
        if (result.found && Number(result.confidence) >= .85)
          return await finish("verified", "external_registry", Math.min(1, Number(result.confidence)), { registry_record_id: result.record_id });
        if (result.definitive === true && result.found === false)
          return await finish("rejected", "external_registry", Math.min(1, Number(result.confidence) || .9), { reason: "definitive_not_found" });
      }
    } catch { /* Резервный источник не должен ломать основную очередь. */ }
  }

  return await finish("needs_review", "manual", .35, { reason: "insufficient_digital_evidence" });
});
