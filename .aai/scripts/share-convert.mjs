#!/usr/bin/env node
// share-convert.mjs — Zero-dependency Markdown → HTML converter for aai-share
// Usage: node share-convert.mjs <source.md> <output-dir>

import { readFileSync, writeFileSync, mkdirSync, copyFileSync, existsSync } from 'fs';
import { dirname, basename, join, resolve, extname } from 'path';

const [,, srcPath, outDir] = process.argv;
if (!srcPath || !outDir) {
  console.error('Usage: node share-convert.mjs <source.md> <output-dir>');
  process.exit(1);
}

const srcAbs = resolve(srcPath);
if (!existsSync(srcAbs)) {
  console.error(`File not found: ${srcAbs}`);
  process.exit(1);
}

const srcDir = dirname(srcAbs);
const title = basename(srcAbs, extname(srcAbs));
const md = readFileSync(srcAbs, 'utf-8');

// --- Markdown → HTML conversion ---

function escapeHtml(s) {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

function convertInline(line) {
  // Images: ![alt](src)
  line = line.replace(/!\[([^\]]*)\]\(([^)]+)\)/g, '<img src="$2" alt="$1">');
  // Links: [text](href)
  line = line.replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2">$1</a>');
  // Bold+Italic: ***text*** or ___text___
  line = line.replace(/\*{3}(.+?)\*{3}/g, '<strong><em>$1</em></strong>');
  line = line.replace(/_{3}(.+?)_{3}/g, '<strong><em>$1</em></strong>');
  // Bold: **text** or __text__
  line = line.replace(/\*{2}(.+?)\*{2}/g, '<strong>$1</strong>');
  line = line.replace(/_{2}(.+?)_{2}/g, '<strong>$1</strong>');
  // Italic: *text* or _text_
  line = line.replace(/\*(.+?)\*/g, '<em>$1</em>');
  line = line.replace(/(?<![a-zA-Z0-9])_(.+?)_(?![a-zA-Z0-9])/g, '<em>$1</em>');
  // Strikethrough: ~~text~~
  line = line.replace(/~~(.+?)~~/g, '<del>$1</del>');
  // Inline code: `code`
  line = line.replace(/`([^`]+)`/g, '<code>$1</code>');
  return line;
}

function convertMarkdown(text) {
  const lines = text.split('\n');
  const out = [];
  let i = 0;

  while (i < lines.length) {
    const line = lines[i];

    // Fenced code blocks: ```lang
    if (/^```/.test(line)) {
      const lang = line.slice(3).trim();
      const codeLines = [];
      i++;
      while (i < lines.length && !/^```/.test(lines[i])) {
        codeLines.push(escapeHtml(lines[i]));
        i++;
      }
      i++; // skip closing ```
      const langAttr = lang ? ` class="language-${escapeHtml(lang)}"` : '';
      out.push(`<pre><code${langAttr}>${codeLines.join('\n')}</code></pre>`);
      continue;
    }

    // Headings: # ... ######
    const headingMatch = line.match(/^(#{1,6})\s+(.+)$/);
    if (headingMatch) {
      const level = headingMatch[1].length;
      out.push(`<h${level}>${convertInline(headingMatch[2])}</h${level}>`);
      i++;
      continue;
    }

    // Horizontal rule: ---, ***, ___
    if (/^(\s*[-*_]\s*){3,}$/.test(line)) {
      out.push('<hr>');
      i++;
      continue;
    }

    // Table: starts with |
    if (/^\|/.test(line) && i + 1 < lines.length && /^\|[\s:|-]+\|$/.test(lines[i + 1].trim())) {
      const headerCells = line.split('|').filter((_, idx, arr) => idx > 0 && idx < arr.length - 1).map(c => c.trim());
      const alignRow = lines[i + 1].split('|').filter((_, idx, arr) => idx > 0 && idx < arr.length - 1).map(c => c.trim());
      const aligns = alignRow.map(c => {
        if (c.startsWith(':') && c.endsWith(':')) return 'center';
        if (c.endsWith(':')) return 'right';
        return 'left';
      });
      let table = '<table>\n<thead><tr>';
      headerCells.forEach((cell, ci) => {
        table += `<th style="text-align:${aligns[ci] || 'left'}">${convertInline(cell)}</th>`;
      });
      table += '</tr></thead>\n<tbody>';
      i += 2; // skip header + separator
      while (i < lines.length && /^\|/.test(lines[i])) {
        const cells = lines[i].split('|').filter((_, idx, arr) => idx > 0 && idx < arr.length - 1).map(c => c.trim());
        table += '\n<tr>';
        cells.forEach((cell, ci) => {
          table += `<td style="text-align:${aligns[ci] || 'left'}">${convertInline(cell)}</td>`;
        });
        table += '</tr>';
        i++;
      }
      table += '\n</tbody></table>';
      out.push(table);
      continue;
    }

    // Blockquote: >
    if (/^>\s?/.test(line)) {
      const bqLines = [];
      while (i < lines.length && /^>\s?/.test(lines[i])) {
        bqLines.push(lines[i].replace(/^>\s?/, ''));
        i++;
      }
      out.push(`<blockquote>${convertMarkdown(bqLines.join('\n'))}</blockquote>`);
      continue;
    }

    // Unordered list: - or * or +
    if (/^(\s*)([-*+])\s+/.test(line)) {
      const listItems = [];
      while (i < lines.length && /^(\s*)([-*+])\s+/.test(lines[i])) {
        listItems.push(convertInline(lines[i].replace(/^\s*[-*+]\s+/, '')));
        i++;
      }
      out.push('<ul>' + listItems.map(li => `<li>${li}</li>`).join('\n') + '</ul>');
      continue;
    }

    // Ordered list: 1. 2. etc
    if (/^\s*\d+\.\s+/.test(line)) {
      const listItems = [];
      while (i < lines.length && /^\s*\d+\.\s+/.test(lines[i])) {
        listItems.push(convertInline(lines[i].replace(/^\s*\d+\.\s+/, '')));
        i++;
      }
      out.push('<ol>' + listItems.map(li => `<li>${li}</li>`).join('\n') + '</ol>');
      continue;
    }

    // Empty line
    if (line.trim() === '') {
      i++;
      continue;
    }

    // Paragraph (collect consecutive non-empty lines)
    const paraLines = [];
    while (i < lines.length && lines[i].trim() !== '' &&
      !/^#{1,6}\s/.test(lines[i]) && !/^```/.test(lines[i]) &&
      !/^\|/.test(lines[i]) && !/^>\s?/.test(lines[i]) &&
      !/^(\s*[-*+])\s+/.test(lines[i]) && !/^\s*\d+\.\s+/.test(lines[i]) &&
      !/^(\s*[-*_]\s*){3,}$/.test(lines[i])) {
      paraLines.push(lines[i]);
      i++;
    }
    if (paraLines.length > 0) {
      out.push(`<p>${convertInline(paraLines.join('\n'))}</p>`);
    }
  }

  return out.join('\n');
}

const htmlContent = convertMarkdown(md);

// --- Collect and copy images ---

mkdirSync(outDir, { recursive: true });

const imgRegex = /!\[[^\]]*\]\(([^)]+)\)/g;
let imgMatch;
let imageCount = 0;
while ((imgMatch = imgRegex.exec(md)) !== null) {
  const imgRef = imgMatch[1];
  // Skip URLs
  if (/^https?:\/\//.test(imgRef) || /^data:/.test(imgRef)) continue;
  const imgSrc = resolve(srcDir, imgRef);
  if (existsSync(imgSrc)) {
    const imgDest = join(outDir, imgRef);
    mkdirSync(dirname(imgDest), { recursive: true });
    copyFileSync(imgSrc, imgDest);
    imageCount++;
  }
}

// --- Write HTML ---

const timestamp = new Date().toISOString().replace('T', ' ').replace(/\.\d+Z$/, ' UTC');

const html = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${escapeHtml(title)}</title>
  <style>
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif;
      line-height: 1.6;
      color: #24292e;
      background-color: #ffffff;
      max-width: 900px;
      margin: 40px auto;
      padding: 20px;
    }
    h1, h2, h3, h4, h5, h6 {
      margin-top: 24px;
      margin-bottom: 16px;
      font-weight: 600;
      line-height: 1.25;
    }
    h1 { font-size: 2em; border-bottom: 1px solid #eaecef; padding-bottom: 0.3em; }
    h2 { font-size: 1.5em; border-bottom: 1px solid #eaecef; padding-bottom: 0.3em; }
    h3 { font-size: 1.25em; }
    code {
      background-color: rgba(27,31,35,0.05);
      border-radius: 3px;
      padding: 0.2em 0.4em;
      font-family: 'SFMono-Regular', Consolas, 'Liberation Mono', Menlo, monospace;
      font-size: 85%;
    }
    pre {
      background-color: #f6f8fa;
      border-radius: 6px;
      padding: 16px;
      overflow: auto;
      line-height: 1.45;
    }
    pre code {
      background-color: transparent;
      padding: 0;
      font-size: 100%;
    }
    img {
      max-width: 100%;
      height: auto;
      border-radius: 6px;
      box-shadow: 0 1px 3px rgba(0,0,0,0.12);
      margin: 20px 0;
    }
    table {
      border-collapse: collapse;
      width: 100%;
      margin: 20px 0;
    }
    table th, table td {
      border: 1px solid #dfe2e5;
      padding: 6px 13px;
    }
    table tr:nth-child(2n) {
      background-color: #f6f8fa;
    }
    blockquote {
      border-left: 4px solid #dfe2e5;
      padding: 0 15px;
      color: #6a737d;
      margin: 20px 0;
    }
    a { color: #0366d6; text-decoration: none; }
    a:hover { text-decoration: underline; }
    ul, ol { padding-left: 2em; }
    li { margin: 4px 0; }
    hr { border: none; border-top: 1px solid #eaecef; margin: 24px 0; }
    del { color: #6a737d; }
    .timestamp {
      color: #6a737d;
      font-size: 0.9em;
      margin-top: 40px;
      padding-top: 20px;
      border-top: 1px solid #eaecef;
    }
  </style>
</head>
<body>
${htmlContent}
  <div class="timestamp">
    Published: ${timestamp}<br>
    Source: ${srcPath}
  </div>
</body>
</html>`;

writeFileSync(join(outDir, 'index.html'), html, 'utf-8');

console.log(`Converted: ${srcPath}`);
console.log(`Output: ${join(outDir, 'index.html')}`);
console.log(`Images: ${imageCount}`);
