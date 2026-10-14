import Link from "next/link";

export default function PurchaseSuccessPage() {
  return (
    <main className="flex min-h-screen items-center justify-center px-6 py-16 font-sans tracking-normal text-neutral-900">
      <section className="w-full max-w-[600px] text-center">
        <div aria-hidden="true" className="mx-auto flex size-14 items-center justify-center rounded-full bg-[#e4efe5] text-2xl text-[#416e4c]">
          ✓
        </div>
        <h1 className="mt-7 text-balance text-4xl font-semibold leading-tight sm:text-5xl">Thanks for choosing Stat.</h1>
        <p className="mx-auto mt-5 max-w-[520px] text-lg leading-8 text-neutral-600">
          Your purchase is in your Polar customer portal. Open it using the link Polar sent to your purchase email.
        </p>
        <p className="mt-3 text-base leading-7 text-neutral-500">
          Personal purchases include a key to unlock Stat on your Mac. For a team purchase, invite teammates from your portal; each person gets their own key after claiming a seat. If you don’t see Polar’s email, check your spam folder.
        </p>
        <a
          href="https://qymrzmmsroxkteaxbgoo.supabase.co/storage/v1/object/public/updates/stat/releases/latest/Stat.dmg"
          download
          className="mt-8 inline-flex items-center justify-center rounded-full bg-neutral-900 px-7 py-3.5 font-medium text-white transition-colors focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-green-500"
        >
          <svg aria-hidden="true" className="size-5 shrink-0" viewBox="0 0 18 20" fill="currentColor">
          <path d="M14.7 10.6c0-2.2 1.8-3.3 1.9-3.4-1-1.5-2.6-1.7-3.2-1.7-1.3-.1-2.6.8-3.3.8-.7 0-1.8-.8-2.9-.8-1.5 0-2.8.9-3.6 2.2-1.5 2.6-.4 6.4 1 8.5.7 1 1.5 2.2 2.6 2.1 1-.1 1.4-.7 2.7-.7s1.7.7 2.8.7c1.2 0 1.9-1 2.6-2.1.8-1.2 1.1-2.4 1.1-2.4s-1.7-.7-1.7-3.2ZM12.5 4.1c.6-.8 1.1-1.9 1-3.1-1 .1-2.2.7-2.9 1.5-.6.7-1.2 1.9-1.1 3 .9.1 2.2-.5 3-1.4Z" />
        </svg>
        &nbsp;
          Download Stat for Mac
        </a>
        {/* <Link className="mt-9 inline-flex items-center justify-center rounded-full bg-neutral-950 px-7 py-3.5 font-medium text-white transition-colors hover:bg-neutral-800 focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-neutral-500" href="/">
          Back to Stat
        </Link> */}
      </section>
    </main>
  );
}
