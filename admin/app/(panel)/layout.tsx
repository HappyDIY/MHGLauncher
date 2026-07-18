import { Shell } from "@/components/shell";
import { requireSession } from "@/lib/session";

export default async function PanelLayout({ children }: { children: React.ReactNode }) {
  const session = await requireSession();
  return <Shell email={session.email}>{children}</Shell>;
}
