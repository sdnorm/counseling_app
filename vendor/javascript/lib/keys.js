// vendor/javascript/lib/keys.js
//
// Everything derived from the password happens here, in the browser. The
// server receives a one-way auth hash and wrapped copies of the data key. It
// never sees the password, the wrapping keys, or the data key itself.

export const MIN_PASSWORD_LENGTH = 12;
export const PBKDF2_ROUNDS = 600000;

const SALT_PREFIX = "client-key-v1:";
const RECOVERY_ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"; // Crockford base32
const RECOVERY_LENGTH = 20;
const AES = { name: "AES-GCM", length: 256 };

const encoder = new TextEncoder();
const subtle = window.crypto.subtle;

export function normalizeEmail(email) {
  return email.trim().toLowerCase();
}

// Salting with the email avoids a pre-login round trip for a per-user salt.
// Emails can't change in this app, so the salt is stable.
async function saltFor(email) {
  const digest = await subtle.digest("SHA-256", encoder.encode(SALT_PREFIX + normalizeEmail(email)));
  return new Uint8Array(digest);
}

// Slow stretch of a secret into HKDF key material. About a second on a phone.
async function stretch(secret, salt) {
  const base = await subtle.importKey("raw", encoder.encode(secret), "PBKDF2", false, ["deriveBits"]);
  const bits = await subtle.deriveBits(
    { name: "PBKDF2", hash: "SHA-256", salt, iterations: PBKDF2_ROUNDS }, base, 256
  );
  return subtle.importKey("raw", bits, "HKDF", false, ["deriveKey", "deriveBits"]);
}

function hkdf(info) {
  return { name: "HKDF", hash: "SHA-256", salt: new Uint8Array(0), info: encoder.encode(info) };
}

function wrappingKeyFrom(material) {
  return subtle.deriveKey(hkdf("wrap"), material, AES, false, ["wrapKey", "unwrapKey"]);
}

// The wrapping key and the auth hash come from the same stretched material
// through HKDF with different labels, so knowing one says nothing about the
// other. Only the auth hash ever leaves the device.
export async function derivePasswordKeys(password, email) {
  const material = await stretch(password, await saltFor(email));
  const wrappingKey = await wrappingKeyFrom(material);
  const authBits = await subtle.deriveBits(hkdf("auth"), material, 256);
  return { wrappingKey, authHash: base64url(authBits) };
}

export async function deriveRecoveryWrappingKey(code, email) {
  const material = await stretch(normalizeRecoveryCode(code), await saltFor(email));
  return wrappingKeyFrom(material);
}

export function generateRecoveryCode() {
  // 256 divides evenly by 32, so a byte mod 32 is uniform.
  const bytes = window.crypto.getRandomValues(new Uint8Array(RECOVERY_LENGTH));
  const chars = Array.from(bytes, (b) => RECOVERY_ALPHABET[b % 32]).join("");
  return chars.match(/.{4}/g).join("-");
}

// Uppercase, strip separators, and fold the look-alikes Crockford excludes so
// a code read back off paper still matches.
export function normalizeRecoveryCode(input) {
  return input.toUpperCase().replace(/[^0-9A-Z]/g, "").replace(/O/g, "0").replace(/[IL]/g, "1");
}

// Extractable so it can be wrapped. Callers pass it through lockDataKey
// before storing it.
export function generateDataKey() {
  return subtle.generateKey(AES, true, ["encrypt", "decrypt"]);
}

export async function wrapDataKey(dataKey, wrappingKey) {
  const nonce = window.crypto.getRandomValues(new Uint8Array(12));
  const wrapped = await subtle.wrapKey("raw", dataKey, wrappingKey, { name: "AES-GCM", iv: nonce });
  return JSON.stringify({ nonce: base64(nonce), ciphertext: base64(wrapped) });
}

// Throws OperationError when the wrapping key is wrong. That is how a wrong
// password or recovery code is detected: nothing is verified server-side.
export async function unwrapDataKey(json, wrappingKey, { extractable = false } = {}) {
  const { nonce, ciphertext } = JSON.parse(json);
  return subtle.unwrapKey(
    "raw", fromBase64(ciphertext), wrappingKey,
    { name: "AES-GCM", iv: fromBase64(nonce) }, AES, extractable, ["encrypt", "decrypt"]
  );
}

// The copy that lives in IndexedDB and does the day-to-day decrypting can't
// be exported. Only the transient handles used for wrapping can.
export async function lockDataKey(extractableKey) {
  const raw = await subtle.exportKey("raw", extractableKey);
  return subtle.importKey("raw", raw, AES, false, ["encrypt", "decrypt"]);
}

function base64(buffer) {
  return btoa(String.fromCharCode(...new Uint8Array(buffer)));
}

function base64url(buffer) {
  return base64(buffer).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function fromBase64(text) {
  return Uint8Array.from(atob(text), (c) => c.charCodeAt(0));
}
