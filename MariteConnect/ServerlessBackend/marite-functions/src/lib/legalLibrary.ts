import { getAppOnlyGraphToken, requireEnv } from "./graphAuth";

// pdf-parse has no type-safe ESM entry point; import lazily via require to keep
// the cold-start cost of the function low when a question needs no PDF text.
// eslint-disable-next-line @typescript-eslint/no-var-requires
const pdfParse = require("pdf-parse");

export interface LegalDocumentMatch {
  documentTitle: string;
  webUrl: string;
  excerpt: string;
}

/**
 * Searches the Sectional Title Legal Library drive (the STSMA, its regulations,
 * and the curated CSOS adjudication orders you upload — see docs/SETUP.md) and
 * returns the most relevant documents with an excerpt of their actual text, so
 * Claude answers from real source material instead of guessing.
 */
export async function findRelevantLegalDocuments(query: string, maxDocuments = 4): Promise<LegalDocumentMatch[]> {
  const token = await getAppOnlyGraphToken();
  const driveId = requireEnv("LEGAL_LIBRARY_DRIVE_ID");

  const searchUrl = `https://graph.microsoft.com/v1.0/drives/${driveId}/root/search(q='${encodeURIComponent(query)}')`;
  const searchResponse = await fetch(searchUrl, { headers: { Authorization: `Bearer ${token}` } });
  if (!searchResponse.ok) {
    throw new Error(`Legal library search failed: ${searchResponse.status} ${await searchResponse.text()}`);
  }

  const searchJson = (await searchResponse.json()) as {
    value: Array<{ id: string; name: string; webUrl: string; file?: { mimeType: string } }>;
  };

  const matches: LegalDocumentMatch[] = [];
  for (const item of searchJson.value.slice(0, maxDocuments)) {
    try {
      const text = await extractText(driveId, item.id, item.file?.mimeType, token);
      matches.push({
        documentTitle: item.name,
        webUrl: item.webUrl,
        excerpt: buildExcerpt(text, query)
      });
    } catch {
      // Skip documents we can't extract text from (e.g. scanned images with no
      // OCR layer) rather than failing the whole request.
      continue;
    }
  }
  return matches;
}

async function extractText(driveId: string, itemId: string, mimeType: string | undefined, token: string): Promise<string> {
  const contentResponse = await fetch(`https://graph.microsoft.com/v1.0/drives/${driveId}/items/${itemId}/content`, {
    headers: { Authorization: `Bearer ${token}` }
  });
  if (!contentResponse.ok) throw new Error(`Could not download document content: ${contentResponse.status}`);

  const buffer = Buffer.from(await contentResponse.arrayBuffer());

  if (mimeType === "application/pdf") {
    const parsed = await pdfParse(buffer);
    return parsed.text as string;
  }
  // Plain text / markdown fallback. Word documents (.docx) aren't handled yet —
  // convert those to PDF before uploading, or extend this with a docx parser
  // such as "mammoth" if the library will hold .docx files.
  return buffer.toString("utf-8");
}

/** Returns a window of text around the first mention of a query keyword, or the
 * document's opening text if no keyword match is found — enough for Claude to
 * ground its answer and for staff to see where the excerpt came from. */
function buildExcerpt(fullText: string, query: string, windowSize = 1200): string {
  const normalized = fullText.replace(/\s+/g, " ").trim();
  const keyword = query.split(/\s+/)[0] ?? "";
  const index = keyword ? normalized.toLowerCase().indexOf(keyword.toLowerCase()) : -1;
  const start = index >= 0 ? Math.max(0, index - windowSize / 4) : 0;
  return normalized.slice(start, start + windowSize);
}
