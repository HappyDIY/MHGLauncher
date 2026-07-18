import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = { title: "MHGLauncher 管理面板", description: "MHGLauncher 云端运营与运维" };

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="zh-CN" suppressHydrationWarning><body>{children}</body></html>;
}
