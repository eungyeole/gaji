const repository = "https://github.com/eungyeole/gaji";
const macDownload = `${repository}/releases/download/nightly/Gaji-macOS.dmg`;
const home = import.meta.env.BASE_URL;
const downloadPage = `${home}download/`;
const companies = {
  Google: "https://cdn.jsdelivr.net/gh/devicons/devicon@latest/icons/google/google-plain-wordmark.svg",
  Samsung: "https://cdn.jsdelivr.net/gh/glincker/thesvg@main/public/icons/samsung/mono.svg",
  Apple: "https://cdn.jsdelivr.net/gh/glincker/thesvg@main/public/icons/apple/mono.svg",
  Tesla: "https://cdn.jsdelivr.net/gh/glincker/thesvg@main/public/icons/tesla/wordmark.svg",
  Netflix: "https://cdn.jsdelivr.net/gh/glincker/thesvg@main/public/icons/netflix/mono.svg",
  LG: "https://cdn.jsdelivr.net/gh/glincker/thesvg@main/public/icons/lg/mono.svg",
  SpaceX: "https://cdn.jsdelivr.net/gh/glincker/thesvg@main/public/icons/spacex/mono.svg",
};
const builders = [["Google", "Samsung", "Apple", "Tesla", "Netflix", "LG", "SpaceX"], ["SpaceX", "LG", "Netflix", "Tesla", "Apple", "Samsung", "Google"]];

function Mark() {
  return <svg viewBox="0 0 40 40" aria-hidden="true"><defs><linearGradient id="gaji-branch" x1="9" y1="7" x2="23" y2="36" gradientUnits="userSpaceOnUse"><stop stopColor="#fff" /><stop offset="1" stopColor="#77787d" /></linearGradient></defs><path d="M20 35c.2-6.4.1-10.7-2.5-15.2-2.1-3.7-5.2-6.7-9-9.3M18.5 22c4-3.1 6.1-7.3 6.2-13.4M19.6 28.5c4.4-1.7 8.5-5.2 12.1-10.2" fill="none" stroke="url(#gaji-branch)" strokeWidth="4.4" strokeLinecap="round" strokeLinejoin="round" /><circle cx="8.5" cy="10.5" r="3.2" fill="#f5f5f7" /><circle cx="24.7" cy="8.6" r="3.2" fill="#c7c7cc" /><circle cx="31.7" cy="18.3" r="3.2" fill="#8e8e93" /></svg>;
}

function Brand({ compact = false }) {
  return <a className="brand" href={home} aria-label="Gaji home">{!compact && <Mark />}<span>Gaji</span></a>;
}

function Navigation() {
  return <header className="nav-shell"><div className="nav shell"><Brand /><nav aria-label="Primary"><a href={downloadPage}>Download</a><a href={repository}>GitHub</a></nav></div></header>;
}

function AppPreview() {
  return <div className="preview-stage"><div className="ambient-orb orb-one" /><div className="ambient-orb orb-two" /><figure className="product-shot"><img src={`${import.meta.env.BASE_URL}gaji-workspace.png`} alt="Gaji showing branches, commit history, and changed files in a native macOS window" /></figure></div>;
}

function Hero() {
  return <section className="hero shell"><h1>Native throughout.</h1><p className="lede">Liquid Glass. Small footprint. Native speed.</p><div className="actions"><a className="button hero-download" href={downloadPage}>Download for macOS <span aria-hidden="true"><img src={companies.Apple} alt="" /></span></a></div><p className="availability">macOS 26+ · Apple silicon and Intel</p><AppPreview /></section>;
}

function Builders() {
  const row = (items, reverse) => <div className="builder-row"><div className={`builder-track${reverse ? " reverse" : ""}`}>{[0, 1, 2, 3, 4].map((copy) => <div className="builder-set" aria-hidden={copy > 0 || undefined} key={copy}>{items.map((name, index) => <span key={`${name}-${index}`}><img src={companies[name]} alt={name} /></span>)}</div>)}</div></div>;
  return <section className="builders" aria-labelledby="builders-title"><p id="builders-title">Trusted by shareholders of</p><div className="builder-marquee">{row(builders[0], false)}{row(builders[1], true)}</div><small>One share still makes you an owner. Technically.</small></section>;
}

function Experience() {
  return <section className="section shell" id="experience"><div className="heading"><p className="eyebrow">Why native</p><h2>Less app. More Mac.</h2><p>No bundled browser runtime—just a compact, responsive Git client built around macOS.</p></div><div className="story-grid">
    <article className="story-card"><p className="story-kicker">Liquid Glass</p><h3>The real thing.</h3><p>System materials, controls, and window behavior make Gaji feel at home on macOS.</p></article>
    <article className="story-card"><p className="story-kicker">Small footprint</p><h3>No browser included.</h3><p>A native interface keeps the app lean and leaves more of your Mac to your work.</p></article>
    <article className="story-card"><p className="story-kicker">Native speed</p><h3>Ready when you are.</h3><p>System UI stays responsive while a fast Rust core handles the repository underneath.</p></article>
  </div></section>;
}

function DownloadPage() {
  return <><Navigation /><main className="download-page"><section className="download-hero shell"><p className="eyebrow">Gaji</p><h1>Download.</h1></section><section className="platform-downloads shell"><article><header><span>Available</span><strong>macOS</strong></header><p>macOS 26+ · Apple silicon and Intel</p><a className="button primary" href={macDownload}>Download DMG</a></article><article className="planned"><header><span>Planned</span><strong>Windows</strong></header><button className="button" disabled>Coming later</button></article></section><p className="install-note shell">Unsigned preview: open from Finder’s context menu the first time.</p></main><footer className="shell"><Brand compact /><p>Native Git for macOS.</p><a href={repository}>GitHub</a></footer></>;
}

export default function App() {
  if (window.location.pathname.endsWith("/download/") || window.location.pathname.endsWith("/download/index.html")) return <DownloadPage />;
  return <><Navigation /><main id="top"><Hero /><Builders /><Experience /></main><footer className="shell"><Brand compact /><p>Native Git for macOS.</p><a href={repository}>GitHub</a></footer></>;
}
