function encodeBase64Url(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/g, "");
}

function decodeBase64Url(value: string): Uint8Array {
  const padded = value.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((value.length + 3) % 4);
  const binary = atob(padded);
  return Uint8Array.from(binary, (char) => char.charCodeAt(0));
}

export async function sha256Hex(input: string): Promise<string> {
  const encoded = new TextEncoder().encode(input);
  const digest = await crypto.subtle.digest("SHA-256", encoded);
  return Array.from(new Uint8Array(digest))
    .map((value) => value.toString(16).padStart(2, "0"))
    .join("");
}

export function createOpaqueToken(byteLength = 32): string {
  const bytes = new Uint8Array(byteLength);
  crypto.getRandomValues(bytes);
  return encodeBase64Url(bytes);
}

async function deriveAesKey(secretMaterial: string): Promise<CryptoKey> {
  const encoded = new TextEncoder().encode(secretMaterial);
  const digest = await crypto.subtle.digest("SHA-256", encoded);
  return crypto.subtle.importKey("raw", digest, "AES-GCM", false, ["encrypt", "decrypt"]);
}

export async function encryptJsonPayload(secretMaterial: string, payload: Record<string, unknown>): Promise<{ ciphertext: string; iv: string }> {
  const key = await deriveAesKey(secretMaterial);
  const iv = new Uint8Array(12);
  crypto.getRandomValues(iv);
  const plaintext = new TextEncoder().encode(JSON.stringify(payload));
  const encrypted = await crypto.subtle.encrypt({ name: "AES-GCM", iv }, key, plaintext);
  return {
    ciphertext: encodeBase64Url(new Uint8Array(encrypted)),
    iv: encodeBase64Url(iv),
  };
}

export async function decryptJsonPayload(secretMaterial: string, encryptedPayload: { ciphertext: string; iv: string }): Promise<Record<string, unknown>> {
  const key = await deriveAesKey(secretMaterial);
  const decrypted = await crypto.subtle.decrypt(
    { name: "AES-GCM", iv: decodeBase64Url(encryptedPayload.iv) },
    key,
    decodeBase64Url(encryptedPayload.ciphertext),
  );
  const parsed = JSON.parse(new TextDecoder().decode(decrypted));
  return typeof parsed === "object" && parsed !== null && !Array.isArray(parsed)
    ? (parsed as Record<string, unknown>)
    : {};
}
