import "dotenv/config";
import { TinyFishClient } from "./tinyfish-client.js";
import { LinkedInScraper } from "./linkedin-scraper.js";

async function main() {
  console.log("🐟 TinyFish Web Agent — LinkedFish Demo\n");

  // --- 1. Raw client: generic extraction with progress ---
  console.log("━━━ Raw Client: Extract product data (streaming) ━━━");
  const client = new TinyFishClient({
    defaultStealth: true,
    defaultProxyCountry: "US",
    onProgress: (action) => console.log(`  ⟩ ${action}`),
  });

  const products = await client.run(
    "https://scrapeme.live/shop",
    "Extract the first 3 product names and prices as a JSON array of {name, price}"
  );
  console.log("Result:", JSON.stringify(products, null, 2));

  // --- 2. LinkedIn scraper: profile extraction ---
  console.log("\n━━━ LinkedIn Scraper: Profile ━━━");
  const scraper = new LinkedInScraper(client);

  const profile = await scraper.getProfile("satya-nadella");
  console.log(`Name:     ${profile.name}`);
  console.log(`Headline: ${profile.headline}`);
  console.log(`Company:  ${profile.company}`);
  console.log(`Location: ${profile.location}`);
  console.log(`Skills:   ${profile.skills.slice(0, 5).join(", ")}`);
  console.log(`Exp:      ${profile.experiences.length} positions`);

  // --- 3. LinkedIn scraper: company extraction ---
  console.log("\n━━━ LinkedIn Scraper: Company ━━━");
  const company = await scraper.getCompany("microsoft");
  console.log(`Name:     ${company.name}`);
  console.log(`Industry: ${company.industry}`);
  console.log(`Size:     ${company.companySize}`);
  console.log(`HQ:       ${company.headquarters}`);

  // --- 4. LinkedIn scraper: job search ---
  console.log("\n━━━ LinkedIn Scraper: Job Search ━━━");
  const jobs = await scraper.searchJobs("AI Engineer", "San Francisco", 3);
  for (const job of jobs) {
    console.log(`  • ${job.title} @ ${job.company} — ${job.location}`);
  }

  console.log("\n✅ Demo complete");
}

main().catch((err) => {
  console.error("❌ Demo failed:", err.message);
  process.exit(1);
});
