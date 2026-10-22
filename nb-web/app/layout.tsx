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
  metadataBase: new URL("https://browser.ink"),
  title: "Ink | Browse without breaking your flow.",
  description:
    "Meet Ink. Your favorite tabs and web apps, right in your Mac’s notch. A seamless, lightweight browser that stays out of your way.",
  applicationName: "Ink",
  icons: { icon: "/app-icon.png", apple: "/app-icon.png" },
  openGraph: {
    title: "Ink | Browse without breaking your flow.",
    description: "Meet Ink. Your favorite tabs and web apps, right in your Mac’s notch.",
    url: "https://browser.ink",
    siteName: "Ink",
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
