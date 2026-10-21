import type { Metadata } from "next";
import Link from "next/link";
import { downloadUrl } from "../../product-links";

export const metadata: Metadata = {
  title: "Download and activate Ink",
  robots: { index: false, follow: false },
};

export default function PurchaseSuccessPage() {
  return (
    <main className="flex min-h-screen items-center justify-center px-6 py-16 font-sans tracking-normal text-neutral-900">
      <section className="w-full max-w-[600px]">
        <p className="text-sm font-medium text-neutral-500">Ink for Mac</p>
        <h1 className="mt-4 text-balance text-4xl font-semibold leading-tight tracking-tight sm:text-5xl">Thanks for choosing Ink.</h1>
        <p className="mt-5 text-lg leading-8 text-neutral-600">
          After checkout, Polar sends your receipt and access to your license key to the email you used to purchase.
        </p>
        <a href={downloadUrl} className="mt-8 inline-flex min-h-12 items-center justify-center rounded-full bg-neutral-900 px-7 py-3.5 font-medium text-white transition-colors hover:bg-neutral-700">
          Download Ink for Mac
        </a>
        <p className="mt-3 text-sm text-neutral-500">macOS 13 or later · Apple silicon &amp; Intel</p>
        <ol className="mt-10 space-y-6 text-base leading-7 text-neutral-600">
          <li><strong className="block font-medium text-neutral-900">1. Install Ink</strong>Open the disk image and drag notch-browser into Applications. The Mac app is currently named Notch Browser.</li>
          <li><strong className="block font-medium text-neutral-900">2. Find your license key</strong>Open the customer portal from Polar’s email, then copy the key for your Ink / NotchBrowser purchase. If the email hasn’t arrived, check your spam folder.</li>
          <li><strong className="block font-medium text-neutral-900">3. Unlock the app</strong>Open Notch Browser from Applications, paste your key into the license window, and choose Unlock. Keep your Mac online for the first activation.</li>
        </ol>
        <p className="mt-8 text-sm leading-6 text-neutral-500">Your license stays in macOS Keychain. You can download the app again from the homepage whenever you need it.</p>
        <Link href="/" className="mt-8 inline-flex text-sm font-medium underline underline-offset-4">Back to Ink</Link>
      </section>
    </main>
  );
}
