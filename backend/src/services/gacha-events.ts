import type { GachaEvent } from "../core/models";
import type { GachaResourceService } from "./gacha-resources";

export class GachaEventService {
  constructor(private readonly resources: GachaResourceService) {}

  list(): GachaEvent[] {
    return this.resources.events().sort((left, right) =>
      String(right.started_at).localeCompare(String(left.started_at)) || left.name.localeCompare(right.name));
  }
}
