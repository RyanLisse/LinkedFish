import { TinyFishClient } from "./tinyfish-client.js";
import type {
  PersonProfile,
  CompanyProfile,
  JobListing,
  JobDetails,
} from "./types.js";

/**
 * LinkedIn-specific data extraction powered by TinyFish Web Agent.
 * Uses stealth mode + proxy by default for bot-protected LinkedIn pages.
 */
export class LinkedInScraper {
  private client: TinyFishClient;

  constructor(client?: TinyFishClient) {
    this.client = client ?? new TinyFishClient({
      defaultStealth: true,
      defaultProxyCountry: "US",
      onProgress: (action) => console.log(`  ⟩ ${action}`),
    });
  }

  /**
   * Extract a person's full LinkedIn profile.
   */
  async getProfile(username: string): Promise<PersonProfile> {
    const url = `https://www.linkedin.com/in/${username}/`;
    const goal = [
      `Extract this person's full LinkedIn profile as JSON with these exact fields:`,
      `name (string), headline (string), about (string), location (string),`,
      `company (string - current company), jobTitle (string - current title),`,
      `experiences (array of {title, company, companyURL, location, startDate, endDate, duration, description}),`,
      `educations (array of {institution, degree, fieldOfStudy, startDate, endDate, description}),`,
      `skills (array of strings),`,
      `profileImageURL (string), backgroundImageURL (string),`,
      `connectionCount (string), followerCount (string),`,
      `openToWork (boolean).`,
      `Return as a single JSON object.`,
    ].join(" ");

    const raw = await this.client.run<Record<string, unknown>>(url, goal);
    return this.normalizeProfile(username, raw);
  }

  /**
   * Extract a company's LinkedIn profile.
   */
  async getCompany(slug: string): Promise<CompanyProfile> {
    const url = `https://www.linkedin.com/company/${slug}/`;
    const goal = [
      `Extract this company's full LinkedIn profile as JSON with these exact fields:`,
      `name (string), tagline (string), about (string), website (string),`,
      `industry (string), companySize (string), headquarters (string),`,
      `founded (string), specialties (array of strings),`,
      `employeeCount (string), followerCount (string),`,
      `logoURL (string), coverImageURL (string).`,
      `Return as a single JSON object.`,
    ].join(" ");

    const raw = await this.client.run<Record<string, unknown>>(url, goal);
    return this.normalizeCompany(slug, raw);
  }

  /**
   * Search for jobs on LinkedIn.
   */
  async searchJobs(
    query: string,
    location?: string,
    limit: number = 10
  ): Promise<JobListing[]> {
    const params = new URLSearchParams({ keywords: query, refresh: "true" });
    if (location) params.set("location", location);
    const url = `https://www.linkedin.com/jobs/search/?${params}`;

    const goal = [
      `Extract the first ${limit} job listings from this search results page as a JSON array.`,
      `Each job object should have: id (string - from the job URL), title (string),`,
      `company (string), companyURL (string), location (string),`,
      `postedDate (string), salary (string or null),`,
      `isEasyApply (boolean), jobURL (string - full URL to the job posting).`,
      `Return as a JSON array.`,
    ].join(" ");

    const raw = await this.client.run<Record<string, unknown>[]>(url, goal);
    return this.normalizeJobListings(raw);
  }

  /**
   * Get detailed info for a specific job posting.
   */
  async getJobDetails(jobId: string): Promise<JobDetails> {
    const url = `https://www.linkedin.com/jobs/view/${jobId}/`;
    const goal = [
      `Extract the full job details from this LinkedIn job posting as JSON with:`,
      `title (string), company (string), companyURL (string), location (string),`,
      `workplaceType (string - Remote/On-site/Hybrid), employmentType (string - Full-time/Part-time/Contract),`,
      `experienceLevel (string), postedDate (string), applicantCount (string),`,
      `salary (string or null), description (string - full job description text),`,
      `skills (array of strings), isEasyApply (boolean), jobURL (string).`,
      `Return as a single JSON object.`,
    ].join(" ");

    const raw = await this.client.run<Record<string, unknown>>(url, goal);
    return this.normalizeJobDetails(jobId, raw);
  }

  // --- Normalizers: coerce raw TinyFish JSON → typed models ---

  private normalizeProfile(
    username: string,
    raw: Record<string, unknown>
  ): PersonProfile {
    return {
      username,
      name: str(raw.name) ?? username,
      headline: str(raw.headline),
      about: str(raw.about),
      location: str(raw.location),
      company: str(raw.company),
      jobTitle: str(raw.jobTitle),
      experiences: arr(raw.experiences).map((e: Record<string, unknown>) => ({
        title: str(e.title) ?? "",
        company: str(e.company) ?? "",
        companyURL: str(e.companyURL),
        location: str(e.location),
        startDate: str(e.startDate),
        endDate: str(e.endDate),
        duration: str(e.duration),
        description: str(e.description),
      })),
      educations: arr(raw.educations).map((e: Record<string, unknown>) => ({
        institution: str(e.institution) ?? "",
        degree: str(e.degree),
        fieldOfStudy: str(e.fieldOfStudy),
        startDate: str(e.startDate),
        endDate: str(e.endDate),
        description: str(e.description),
      })),
      skills: arr(raw.skills).map((s: unknown) =>
        typeof s === "string" ? s : String(s)
      ),
      profileImageURL: str(raw.profileImageURL),
      backgroundImageURL: str(raw.backgroundImageURL),
      connectionCount: str(raw.connectionCount),
      followerCount: str(raw.followerCount),
      openToWork: raw.openToWork === true,
    };
  }

  private normalizeCompany(
    slug: string,
    raw: Record<string, unknown>
  ): CompanyProfile {
    return {
      name: str(raw.name) ?? slug,
      slug,
      tagline: str(raw.tagline),
      about: str(raw.about),
      website: str(raw.website),
      industry: str(raw.industry),
      companySize: str(raw.companySize),
      headquarters: str(raw.headquarters),
      founded: str(raw.founded),
      specialties: arr(raw.specialties).map((s: unknown) =>
        typeof s === "string" ? s : String(s)
      ),
      employeeCount: str(raw.employeeCount),
      followerCount: str(raw.followerCount),
      logoURL: str(raw.logoURL),
      coverImageURL: str(raw.coverImageURL),
    };
  }

  private normalizeJobListings(
    raw: Record<string, unknown>[]
  ): JobListing[] {
    return raw.map((j) => ({
      id: str(j.id) ?? "",
      title: str(j.title) ?? "",
      company: str(j.company) ?? "",
      companyURL: str(j.companyURL),
      location: str(j.location),
      postedDate: str(j.postedDate),
      salary: str(j.salary),
      isEasyApply: j.isEasyApply === true,
      jobURL: str(j.jobURL) ?? "",
    }));
  }

  private normalizeJobDetails(
    jobId: string,
    raw: Record<string, unknown>
  ): JobDetails {
    return {
      id: jobId,
      title: str(raw.title) ?? "",
      company: str(raw.company) ?? "",
      companyURL: str(raw.companyURL),
      location: str(raw.location),
      workplaceType: str(raw.workplaceType),
      employmentType: str(raw.employmentType),
      experienceLevel: str(raw.experienceLevel),
      postedDate: str(raw.postedDate),
      applicantCount: str(raw.applicantCount),
      salary: str(raw.salary),
      description: str(raw.description),
      skills: arr(raw.skills).map((s: unknown) =>
        typeof s === "string" ? s : String(s)
      ),
      isEasyApply: raw.isEasyApply === true,
      jobURL: str(raw.jobURL) ?? `https://www.linkedin.com/jobs/view/${jobId}/`,
    };
  }
}

// Helpers for safe coercion of unknown API responses
function str(v: unknown): string | undefined {
  if (typeof v === "string" && v.length > 0) return v;
  if (typeof v === "number") return String(v);
  return undefined;
}

function arr(v: unknown): Record<string, unknown>[] {
  return Array.isArray(v) ? v : [];
}
