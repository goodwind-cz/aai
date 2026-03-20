import fs from "node:fs";

type Scalar = string | number | boolean;
type YamlMap = {
  [key: string]: YamlValue;
};
type YamlValue = Scalar | YamlMap;

function parseScalar(rawValue: string): Scalar {
  const value = rawValue.trim();
  if (value === "true") {
    return true;
  }
  if (value === "false") {
    return false;
  }
  if (/^-?\d+$/.test(value)) {
    return Number.parseInt(value, 10);
  }
  if (/^-?\d+\.\d+$/.test(value)) {
    return Number.parseFloat(value);
  }
  return value.replace(/^['"]|['"]$/g, "");
}

export function parseYamlDocument(source: string): Record<string, YamlValue> {
  const result: Record<string, YamlValue> = {};
  const stack: Array<{ indent: number; value: YamlMap }> = [{ indent: -1, value: result }];

  for (const originalLine of source.split(/\r?\n/)) {
    const line = originalLine.replace(/\t/g, "  ");
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) {
      continue;
    }

    const indent = line.length - line.trimStart().length;
    while (stack.length > 1 && indent <= stack[stack.length - 1].indent) {
      stack.pop();
    }

    const currentObject = stack[stack.length - 1].value;
    const separatorIndex = trimmed.indexOf(":");
    if (separatorIndex === -1) {
      throw new Error(`Unsupported YAML line: ${originalLine}`);
    }

    const key = trimmed.slice(0, separatorIndex).trim();
    const valuePart = trimmed.slice(separatorIndex + 1).trim();

    if (!valuePart) {
      currentObject[key] = {};
      stack.push({ indent, value: currentObject[key] as YamlMap });
      continue;
    }

    currentObject[key] = parseScalar(valuePart);
  }

  return result;
}

export function loadYamlFile(filePath: string): Record<string, YamlValue> {
  return parseYamlDocument(fs.readFileSync(filePath, "utf8"));
}
