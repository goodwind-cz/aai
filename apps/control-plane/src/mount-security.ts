import fs from "node:fs";
import os from "node:os";
import path from "node:path";

export type AllowedRoot = {
  path: string;
  allowReadWrite: boolean;
  description?: string;
};

export type MountAllowlist = {
  allowedRoots: AllowedRoot[];
  blockedPatterns: string[];
  nonMainReadOnly: boolean;
};

export type RequestedMount = {
  source: string;
  target: string;
  read_only: boolean;
};

export type ValidatedMount = RequestedMount & {
  source: string;
};

const DEFAULT_BLOCKED_PATTERNS = [
  ".ssh",
  ".gnupg",
  ".gpg",
  ".aws",
  ".azure",
  ".kube",
  ".docker",
  ".env",
  ".netrc",
  "id_rsa",
  "id_ed25519",
  "private_key",
  "secret",
  "token"
];

export const DEFAULT_MOUNT_ALLOWLIST_PATH = path.join(
  os.homedir(),
  ".config",
  "aai-control-plane",
  "mount-allowlist.json"
);

function expandPath(inputPath: string): string {
  if (inputPath === "~") {
    return os.homedir();
  }
  if (inputPath.startsWith("~/")) {
    return path.join(os.homedir(), inputPath.slice(2));
  }
  return path.resolve(inputPath);
}

function realPathOrNull(inputPath: string): string | null {
  try {
    return fs.realpathSync(inputPath);
  } catch {
    return null;
  }
}

function matchesBlockedPattern(realPath: string, blockedPatterns: string[]): string | null {
  const pathParts = realPath.split(path.sep);
  for (const pattern of blockedPatterns) {
    if (pathParts.some((part) => part === pattern || part.includes(pattern))) {
      return pattern;
    }
    if (realPath.includes(pattern)) {
      return pattern;
    }
  }
  return null;
}

function isSafeContainerTarget(target: string): boolean {
  if (!target || target.trim() === "") {
    return false;
  }
  if (!target.startsWith("/")) {
    return false;
  }
  return !target.includes("..");
}

function findAllowedRoot(realMountPath: string, allowedRoots: AllowedRoot[]): AllowedRoot | null {
  for (const root of allowedRoots) {
    const resolvedRoot = realPathOrNull(expandPath(root.path));
    if (!resolvedRoot) {
      continue;
    }
    const relative = path.relative(resolvedRoot, realMountPath);
    if (!relative.startsWith("..") && !path.isAbsolute(relative)) {
      return root;
    }
  }
  return null;
}

export function loadMountAllowlist(filePath = DEFAULT_MOUNT_ALLOWLIST_PATH): MountAllowlist {
  const content = fs.readFileSync(filePath, "utf8");
  const parsed = JSON.parse(content) as MountAllowlist;
  if (!Array.isArray(parsed.allowedRoots)) {
    throw new Error("Mount allowlist requires allowedRoots array");
  }
  if (!Array.isArray(parsed.blockedPatterns)) {
    throw new Error("Mount allowlist requires blockedPatterns array");
  }
  if (typeof parsed.nonMainReadOnly !== "boolean") {
    throw new Error("Mount allowlist requires nonMainReadOnly boolean");
  }

  return {
    allowedRoots: parsed.allowedRoots,
    blockedPatterns: [...new Set([...DEFAULT_BLOCKED_PATTERNS, ...parsed.blockedPatterns])],
    nonMainReadOnly: parsed.nonMainReadOnly
  };
}

export function validateMount(
  mount: RequestedMount,
  allowlist: MountAllowlist,
  isMainProject: boolean
): { allowed: boolean; reason: string; mount?: ValidatedMount } {
  if (!isSafeContainerTarget(mount.target)) {
    return { allowed: false, reason: `Invalid container target: ${mount.target}` };
  }

  const resolvedSource = realPathOrNull(expandPath(mount.source));
  if (!resolvedSource) {
    return { allowed: false, reason: `Mount source does not exist: ${mount.source}` };
  }

  const blockedPattern = matchesBlockedPattern(resolvedSource, allowlist.blockedPatterns);
  if (blockedPattern) {
    return { allowed: false, reason: `Mount source matches blocked pattern: ${blockedPattern}` };
  }

  const allowedRoot = findAllowedRoot(resolvedSource, allowlist.allowedRoots);
  if (!allowedRoot) {
    return { allowed: false, reason: `Mount source is outside allowed roots: ${resolvedSource}` };
  }

  const effectiveReadOnly =
    mount.read_only || (!isMainProject && allowlist.nonMainReadOnly) || !allowedRoot.allowReadWrite;

  return {
    allowed: true,
    reason: `Allowed under ${allowedRoot.path}`,
    mount: {
      source: resolvedSource,
      target: mount.target,
      read_only: effectiveReadOnly
    }
  };
}

export function validateMounts(
  mounts: RequestedMount[],
  allowlist: MountAllowlist,
  isMainProject: boolean
): { accepted: ValidatedMount[]; rejected: Array<{ mount: RequestedMount; reason: string }> } {
  const accepted: ValidatedMount[] = [];
  const rejected: Array<{ mount: RequestedMount; reason: string }> = [];

  for (const mount of mounts) {
    const result = validateMount(mount, allowlist, isMainProject);
    if (result.allowed && result.mount) {
      accepted.push(result.mount);
      continue;
    }
    rejected.push({ mount, reason: result.reason });
  }

  return { accepted, rejected };
}

export function generateAllowlistTemplate(): MountAllowlist {
  return {
    allowedRoots: [
      {
        path: "~/projects",
        allowReadWrite: true,
        description: "Project worktrees and repositories"
      },
      {
        path: "~/Documents/specs",
        allowReadWrite: false,
        description: "Read-only supporting documents"
      }
    ],
    blockedPatterns: ["password", "credential"],
    nonMainReadOnly: true
  };
}
