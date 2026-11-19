#!/usr/bin/env node
/**
 * Builds public/channel-icons.json, the channel icon manifest consumed by the
 * T-Connect mobile app at runtime.
 *
 * The web dashboard compiles its icons into CSS at build time, so nothing in
 * the running server exposes them. This script reads the same sources the
 * dashboard uses and writes them out as plain Iconify data, so the mobile app
 * draws exactly the glyphs the web does:
 *
 *   - which icon each channel uses  <- app/javascript/dashboard/components-next/icon/provider.js
 *                                      app/javascript/dashboard/helper/inbox.js (voice glyphs)
 *   - the custom `woot` glyphs      <- theme/icons.js
 *   - brand/line sets (logos, ri…)  <- node_modules/@iconify-json/<set>/icons.json
 *
 * Usage: node scripts/generate-channel-icons.mjs
 * Re-run it (and deploy public/channel-icons.json) whenever the web changes a
 * channel icon. The manifest `version` only changes when the icon data does.
 */
import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const read = rel => readFileSync(resolve(root, rel), 'utf8');

const PROVIDER_FILE = 'app/javascript/dashboard/components-next/icon/provider.js';
const INBOX_FILE = 'app/javascript/dashboard/helper/inbox.js';
const OUTPUT_FILE = 'public/channel-icons.json';

// Pulls `const <name> = { 'key': 'value', ... }` literal maps out of a source file.
const parseStringMap = (source, name) => {
  const match = source.match(new RegExp(`(?:const|export const) ${name} = \\{([\\s\\S]*?)\\n\\};`));
  if (!match) throw new Error(`Could not find map "${name}"`);
  const map = {};
  for (const entry of match[1].matchAll(/['"]([^'"]+)['"]\s*:\s*['"]([^'"]+)['"]/g)) {
    map[entry[1]] = entry[2];
  }
  return map;
};

const provider = read(PROVIDER_FILE);
const inbox = read(INBOX_FILE);

const line = parseStringMap(provider, 'channelTypeIconMap');
const brand = parseStringMap(provider, 'channelTypeBrandIconMap');
const providerLine = parseStringMap(provider, 'providerIconMap');
const providerBrand = parseStringMap(provider, 'providerBrandIconMap');
// VOICE_CALL_ICONS is keyed by computed `[VOICE_CALL_PROVIDERS.X]`, so read the glyphs directly.
const voiceIcons = {
  twilio: inbox.match(/\[VOICE_CALL_PROVIDERS\.TWILIO\]:\s*'([^']+)'/)?.[1],
  whatsapp: inbox.match(/\[VOICE_CALL_PROVIDERS\.WHATSAPP\]:\s*'([^']+)'/)?.[1],
};
const WHATSAPP_GLYPH = 'i-woot-whatsapp';
const FALLBACK_GLYPH = 'i-ri-global-fill';

const wootModule = await import(pathToFileURL(resolve(root, 'theme/icons.js')).href);
const collectionCache = {};

const loadCollection = set => {
  collectionCache[set] ??= JSON.parse(
    readFileSync(resolve(root, `node_modules/@iconify-json/${set}/icons.json`), 'utf8'),
  );
  return collectionCache[set];
};

// 'i-woot-zalo' -> { set: 'woot', name: 'zalo' }; 'i-logos-messenger' -> { set: 'logos', ... }
const splitName = icon => {
  const [, set, ...rest] = icon.split('-');
  return { set, name: rest.join('-') };
};

const resolveIcon = icon => {
  const { set, name } = splitName(icon);
  if (set === 'woot') {
    const data = wootModule.icons[name];
    if (!data) throw new Error(`Missing woot icon "${name}"`);
    return { body: data.body, width: data.width ?? 24, height: data.height ?? 24 };
  }
  const collection = loadCollection(set);
  let data = collection.icons[name];
  if (!data && collection.aliases?.[name]) {
    const alias = collection.aliases[name];
    data = { ...collection.icons[alias.parent], ...alias };
  }
  if (!data) throw new Error(`Missing ${set} icon "${name}"`);
  return {
    body: data.body,
    width: data.width ?? collection.width ?? 16,
    height: data.height ?? collection.height ?? 16,
  };
};

const used = new Set([
  ...Object.values(line),
  ...Object.values(brand),
  ...Object.values(providerLine),
  ...Object.values(providerBrand),
  ...Object.values(voiceIcons),
  WHATSAPP_GLYPH,
  FALLBACK_GLYPH,
]);

const icons = {};
for (const icon of [...used].sort()) icons[icon] = resolveIcon(icon);

const content = {
  line,
  brand,
  providerLine,
  providerBrand,
  voice: voiceIcons,
  twilioWhatsapp: WHATSAPP_GLYPH,
  fallback: FALLBACK_GLYPH,
  icons,
};

const version = createHash('sha1').update(JSON.stringify(content)).digest('hex').slice(0, 12);
writeFileSync(
  resolve(root, OUTPUT_FILE),
  `${JSON.stringify({ version, ...content }, null, 2)}\n`,
);

console.log(`Wrote ${OUTPUT_FILE} (version ${version}, ${Object.keys(icons).length} icons)`);
