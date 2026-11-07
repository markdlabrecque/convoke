// Model choice. AGENT.modelLabels (config.mts) maps ticket labels to models. Empty: one fixed model,
// AGENT.model, for every run. Non-empty: the ticket's single model label picks the implementer's
// model, and those models are the only ones allowed anywhere (AGENT.model, GRAPH.model).

/** The implementer's model for a ticket, or why it has none. */
export function ticketModel(labels: string[], modelLabels: Record<string, string>, fixed: string): { model: string } | { error: string } {
  const choices = Object.keys(modelLabels);
  if (!choices.length) return { model: fixed };
  const found = labels.filter((l) => l in modelLabels);
  if (found.length === 1) return { model: modelLabels[found[0]] };
  const list = choices.join(", ");
  return { error: found.length ? `has ${found.length} model labels (${found.join(", ")}); keep one of ${list}` : `needs a model label: one of ${list}` };
}

/** Configured models outside the allowlist, as an error message; undefined when all are allowed. */
export function disallowedModels(modelLabels: Record<string, string>, configured: string[]): string | undefined {
  const allowed = new Set(Object.values(modelLabels));
  if (!allowed.size) return undefined;
  const bad = configured.filter((m) => !allowed.has(m));
  return bad.length ? `model(s) ${bad.join(", ")} are not in AGENT.modelLabels (${[...allowed].join(", ")}); config.mts may only use those.` : undefined;
}
