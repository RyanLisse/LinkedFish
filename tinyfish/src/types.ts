// TinyFish SSE Event Types

export interface SSEProgressEvent {
  type: "PROGRESS";
  purpose: string;
  timestamp?: string;
}

export interface SSECompleteEvent {
  type: "COMPLETE";
  status: "COMPLETED" | "FAILED" | "TIMEOUT";
  resultJson?: unknown;
  result?: string;
  error?: { message: string; code?: string };
}

export type SSEEvent = SSEProgressEvent | SSECompleteEvent;

// TinyFish API Request Options

export interface TinyFishOptions {
  url: string;
  goal: string;
  browser_profile?: "stealth" | "default";
  proxy_config?: {
    enabled: boolean;
    country_code?: "US" | "GB" | "CA" | "DE" | "FR" | "JP" | "AU";
  };
}

// LinkedIn Data Models — mirrors Sources/LinkLion/Models.swift

export interface PersonProfile {
  username: string;
  name: string;
  headline?: string;
  about?: string;
  location?: string;
  company?: string;
  jobTitle?: string;
  experiences: Experience[];
  educations: Education[];
  skills: string[];
  profileImageURL?: string;
  backgroundImageURL?: string;
  connectionCount?: string;
  followerCount?: string;
  openToWork: boolean;
}

export interface Experience {
  title: string;
  company: string;
  companyURL?: string;
  location?: string;
  startDate?: string;
  endDate?: string;
  duration?: string;
  description?: string;
}

export interface Education {
  institution: string;
  degree?: string;
  fieldOfStudy?: string;
  startDate?: string;
  endDate?: string;
  description?: string;
}

export interface CompanyProfile {
  name: string;
  slug: string;
  tagline?: string;
  about?: string;
  website?: string;
  industry?: string;
  companySize?: string;
  headquarters?: string;
  founded?: string;
  specialties: string[];
  employeeCount?: string;
  followerCount?: string;
  logoURL?: string;
  coverImageURL?: string;
}

export interface JobListing {
  id: string;
  title: string;
  company: string;
  companyURL?: string;
  location?: string;
  postedDate?: string;
  salary?: string;
  isEasyApply: boolean;
  jobURL: string;
}

export interface JobDetails extends JobListing {
  workplaceType?: string;
  employmentType?: string;
  experienceLevel?: string;
  applicantCount?: string;
  description?: string;
  skills: string[];
}
