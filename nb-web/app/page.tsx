import Image from "next/image";
import type { ReactNode } from "react";
import DemoVideo from "./demo-video";
import FeatureVideo from "./feature-video";
import BrowserComparison from "./browser-comparison";
import WhyNotFree from "./why-not-free";

const checkoutUrl = "https://buy.polar.sh/polar_cl_h61CaUncTVTTbKDnENNCs7cizvFTBYopQmWaS15R88r";
const brands = ["Datadog", "Figma", "Ramp", "Adobe", "Stripe", "Amazon"];

function Arrow({ className = "" }: { className?: string }) {
  return (
    <svg className={className} width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d="M4 12h16m-6-6 6 6-6 6" />
    </svg>
  );
}

function AppMark({ size = 40 }: { size?: number }) {
  return <Image src="/app-icon.png" width={size} height={size} alt="" className="rounded-full" />;
}

function BuyLink({ children, small = false }: { children: ReactNode; small?: boolean }) {
  return (
    <a href={checkoutUrl} className={`inline-flex items-center justify-center gap-3 rounded-full bg-[#111] font-medium text-white transition-colors hover:bg-[#333] ${small ? "min-h-10 px-4 text-[14px]" : "min-h-12 px-6 text-[15px]"}`}>
      {children}
      {!small && <Arrow />}
    </a>
  );
}

export default function Home() {
  return (
    <>
      <a href="#main" className="sr-only fixed left-4 top-4 z-50 rounded-md bg-black px-4 py-3 text-white focus:not-sr-only">Skip to content</a>
      <header className="sticky top-4 z-30 mx-4 mt-8 flex max-w-[800px] items-center justify-between gap-3 rounded-full border border-neutral-200 bg-white/95 px-4 py-3 backdrop-blur-md sm:mx-auto sm:mt-10 sm:gap-4 sm:px-7">
        <a href="#main" aria-label="Notch Browser home" className="flex shrink-0 items-center gap-2 text-[16px] font-medium tracking-[-0.035em] sm:text-[19px]">
          <AppMark size={24} />
          <span>Notch Browser</span>
        </a>
        <nav aria-label="Main navigation" className="flex shrink-0 items-center gap-5 text-[13px] font-medium">
          <a href="#features" className="hidden transition-colors hover:text-[#777] sm:block">Features</a>
          <a href="#agents" className="hidden transition-colors hover:text-[#777] sm:block">For agents</a>
          <a href="#pricing" className="hidden transition-colors hover:text-[#777] md:block">Pricing</a>
          <BuyLink small><span aria-hidden="true"></span> Buy Now</BuyLink>
        </nav>
      </header>

      <main id="main">
        <section className="mx-auto max-w-[1120px] px-6 pb-10 pt-20 text-center sm:px-10 sm:pb-12 sm:pt-24 lg:pt-28" aria-labelledby="hero-title">
          <h1 id="hero-title" className="mx-auto max-w-[600px] text-balance text-[56px] font-black leading-[0.88] tracking-tighter sm:text-[80px] lg:text-8xl">
            Safari <Image src="/safari.png" width={72} height={72} alt="" className="-mx-1 -mt-3 inline-block size-12 rounded-md sm:-mx-2 sm:-mt-5 sm:size-16 lg:size-18" />
            <span> in your notch.</span>
          </h1>
          <p className="mx-auto mt-7 max-w-[560px] text-balance text-[16px] leading-[1.7] text-[#666] sm:text-[17px]">For the quick searches, small tasks, and tabs you don’t need all day. Now your agent can use it, too.</p>
          <div className="mt-7 flex flex-wrap items-center justify-center gap-x-6 gap-y-3">
            <BuyLink><span aria-hidden="true"></span> Get for Mac — $5</BuyLink>
            {/* <a href="#demo" className="inline-flex min-h-12 items-center gap-2 text-[14px] font-medium transition-colors hover:text-[#777]">Watch the demo<Arrow /></a> */}
          </div>
          {/* <p className="mt-4 text-[12px] text-[#888]">One-time purchase · Native macOS app · CLI & skills included</p> */}
        </section>

        <section id="demo" className="mx-auto max-w-[1120px] scroll-mt-24 px-6 sm:px-10" aria-label="See Notch Browser in action">
          <DemoVideo />
        </section>

        <section id="logo-garden" aria-labelledby="brands-title" className="mx-auto max-w-[1120px] my-20 px-6 pb-16 pt-10 sm:px-10 sm:pb-20 sm:pt-12">
          <h2 id="brands-title" className="text-center text-[13px] font-medium text-[#888]">Being used by productivity folks at.</h2>
          <ul className="mt-5 grid grid-cols-2 items-center gap-x-4 gap-y-1 sm:grid-cols-4 lg:grid-cols-6">
            {brands.map((brand) => (
              <li key={brand} className="flex h-16 min-w-0 items-center justify-center px-2">
                <Image src={`/brands/${brand.toLowerCase()}.svg`} width={140} height={60} alt={brand} className="h-12 w-full max-w-[120px] object-contain opacity-60" />
              </li>
            ))}
          </ul>
        </section>

        <BrowserComparison />

        <section id="features" aria-labelledby="features-title" className="mx-auto max-w-[1120px] scroll-mt-28 px-6 sm:px-10">
          <div className="mx-auto max-w-[800px] pb-12 text-center sm:pb-16">
            <h2 id="features-title" className="section-heading tracking-tighter font-black text-balance">Your browser, wherever you need it.</h2>
            <p className="mx-auto mt-5 max-w-[660px] text-balance text-[16px] leading-[1.7] text-[#777] sm:text-[18px]">A little space for your everyday web. Browse, watch, and let your agent lend a hand — all from your Mac’s notch.</p>
            <ul className="mt-6 flex flex-wrap justify-center gap-2">
              {["Light & fast", "Everyday tabs", "Hover to open", "Embed mode", "Agent native", "CLI included"].map((feature) => (
                <li key={feature} className="rounded-full bg-[#f5f5f5] px-3.5 py-2 text-[12px] text-[#666]">{feature}</li>
              ))}
            </ul>
          </div>

          <div className="grid gap-10 sm:gap-14">
            <article className="showcase-panel" aria-labelledby="browsing-title">
              <div className="mx-auto max-w-[800px] pb-7 text-center sm:pb-9">
                <p className="mb-3 text-[12px] font-medium text-[#888]">Quick & light</p>
                <h3 id="browsing-title" className="showcase-heading text-balance">Your everyday tabs. Just a hover away.</h3>
                <p className="mx-auto mt-4 max-w-[640px] text-balance text-[15px] leading-[1.7] text-[#777] sm:text-[16px]">Look something up, check a tab, take a little break. Open your browser without leaving what you’re doing.</p>
              </div>
              <FeatureVideo src="/demo1.mp4" poster="/demo1-poster.jpg" label="everyday browsing demo" />
            </article>

            <article className="showcase-panel" aria-labelledby="embed-title">
              <div className="mx-auto max-w-[800px] pb-7 text-center sm:pb-9">
                <p className="mb-3 text-[12px] font-medium text-[#888]">Embed mode</p>
                <h3 id="embed-title" className="showcase-heading text-balance">Your web apps. A notch closer.</h3>
                <p className="mx-auto mt-4 max-w-[640px] text-balance text-[15px] leading-[1.7] text-[#777] sm:text-[16px]">Hide the browser controls and let your favorite web apps settle in. Watch, listen, or unwind in a space of your own.</p>
              </div>
              <FeatureVideo src="/demo2.mp4" poster="/demo2-poster.jpg" label="web apps in the notch demo" />
            </article>
          </div>
        </section>

        {/* <section id="agents" aria-labelledby="agents-title" className="mx-auto max-w-[1120px] scroll-mt-28 px-6 py-16 text-center sm:px-10 sm:py-24">
          <p className="mb-4 text-[12px] font-medium text-[#888]">Agent native</p>
          <h2 id="agents-title" className="section-heading mx-auto max-w-[720px] text-balance">Your browser. Your agent’s, too.</h2>
          <p className="mx-auto mt-5 max-w-[620px] text-balance text-[16px] leading-[1.7] text-[#777]">Let Codex or Claude Code read pages, follow links, and fill forms in your own browser. Watch it happen, or keep the notch collapsed and carry on.</p>
          <div id="agent-setup" className="mt-6 scroll-mt-28">
            <a href="/skills/notch-browser/SKILL.md" download="SKILL.md" className="inline-flex min-h-11 items-center gap-2 rounded-full border border-[#e5e5e5] px-5 text-[13px] font-medium transition-colors hover:bg-[#f5f5f5]">Download the agent skill<Arrow /></a>
          </div>
        </section> */}

        <section id="pricing" aria-labelledby="pricing-title" 
        className="mx-auto max-w-[1120px] scroll-mt-28 px-6 pb-16 sm:px-10 sm:pb-24 flex flex-col items-center 
        justify-center mt-40">
          <a href={checkoutUrl} className="w-full max-w-[900px] py-20 px-5 bg-black text-white rounded-full cursor-pointer
          flex items-center justify-center">
            <h1 className="text-7xl tracking-tighter font-bold">
               Buy Now for $5
              {/* <span className="line-through text-xl">$19</span>  */}
              {/* <span className="text-green-500">$5</span> */}
            </h1>
          </a>
          {/* <WhyNotFree /> */}
        </section>

        <section id="faq" aria-labelledby="faq-title" className="mx-auto max-w-[1120px] px-6 pb-20 sm:px-10 sm:pb-28">
          <h2 id="faq-title" className="text-center text-[32px] font-bold tracking-[-0.045em] sm:text-[40px]">A few little details.</h2>
          <div className="mx-auto mt-8 max-w-[740px] divide-y divide-[#e9e9e9] border-y border-[#e9e9e9]">
            {[
              ["How many tabs can it handle?", "There’s no fixed tab limit. Keep the tabs you need close by, though Notch Browser is designed for a focused handful of everyday tabs rather than dozens of heavy pages. How many run comfortably depends on your Mac and the sites you open."],
              ["Do I need to sign in to every site again?", "Chrome import can bring over your cookies and signed-in sessions during setup, so you don’t have to start from scratch. Some sites may still ask you to sign in again. Safari currently imports bookmarks; you’ll need to sign in to those sites again."],
              ["Can it launch at login?", "Yes. Turn on Launch at Login in the app’s menu and Notch Browser will be ready when you sign in to your Mac."],
              ["Can I embed any web app into the notch?", "Yes. Open your web app and switch to Embed mode to hide the browser controls. Your AI chat, music player, notes, or documentation can stay in the notch, just a hover away."],
              ["How is it agent native?", "Notch Browser includes a command-line tool and skills for Codex and Claude Code. Your agent can open tabs, read pages, follow links, fill forms, and capture screenshots in your browser — even while the notch is collapsed. Keep the app running while your agent works."],
            ].map(([question, answer]) => (
              <details key={question} className="group py-5">
                <summary className="flex cursor-pointer list-none items-start justify-between gap-6 text-[14px] font-medium leading-6 sm:text-[15px]">{question}<span className="shrink-0 text-[#999] transition-transform group-open:rotate-45" aria-hidden="true">+</span></summary>
                <p className="mt-3 max-w-[650px] pr-6 text-[14px] leading-[1.8] text-[#777]">{answer}</p>
              </details>
            ))}
          </div>
        </section>
      </main>

      <footer className="mx-auto flex max-w-[1120px] flex-col gap-7 border-t border-[#e9e9e9] px-6 pb-9 pt-9 sm:px-10 md:flex-row md:items-center md:justify-between">
        <div>
          <a href="#main" className="flex items-center gap-2.5 text-[16px] font-semibold tracking-[-0.035em]"><AppMark size={30} /><span>Notch Browser</span></a>
          <p className="mt-3 text-[13px] text-[#777]">Made for the little things.</p>
        </div>
        <div className="flex flex-wrap items-center gap-x-5 gap-y-3 text-[13px] text-[#777]">
          <a href="#features" className="hover:text-black">Features</a>
          <a href="#agents" className="hover:text-black">For agents</a>
          <a href="#faq" className="hover:text-black">FAQ</a>
          <a href={checkoutUrl} className="hover:text-black">Get for Mac <span aria-hidden="true">↗</span></a>
          <span>© 2026 Govi</span>
        </div>
      </footer>
    </>
  );
}
