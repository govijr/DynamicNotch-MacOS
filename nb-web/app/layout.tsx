import type { Metadata } from "next";
import localFont from "next/font/local";
import "./globals.css";

const notionInter = localFont({
  src: [
    { path: "./fonts/NotionInter-Regular.woff2", weight: "400", style: "normal" },
    { path: "./fonts/NotionInter-Medium.woff2", weight: "500", style: "normal" },
    { path: "./fonts/NotionInter-SemiBold.woff2", weight: "600", style: "normal" },
    { path: "./fonts/NotionInter-Bold.woff2", weight: "700", style: "normal" },
  ],
  variable: "--font-notion-inter",
  display: "swap",
});

export const metadata: Metadata = {
  title: "Notch Browser — A little browser. Right in your notch.",
  description:
    "A lightweight browser in your Mac’s notch, for you and your AI agent. Let Codex or Claude Code browse, read pages, and take action—even while the notch is collapsed. CLI and skills included.",
  applicationName: "Notch Browser",
  icons: { icon: "/app-icon.png", apple: "/app-icon.png" },
  openGraph: {
    title: "Notch Browser — A little browser. Right in your notch.",
    description: "Your browser. Your agent’s, too. Browse in the background with Codex or Claude Code. CLI and skills included in the Mac app.",
    type: "website",
    locale: "en_US",
  },
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={`${notionInter.variable} antialiased`}>
      <body>{children}</body>
    </html>
  );
}
