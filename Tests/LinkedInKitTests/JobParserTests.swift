import XCTest
@testable import LinkLion

final class JobParserTests: XCTestCase {

    // MARK: - Job Search Results

    func testParseJobListingsFromHTML() throws {
        let html = try loadFixture("job_listing")
        let jobs = try JobParser.parseJobSearch(html: html)

        // We have 4 job cards but the 4th uses data-entity-urn fallback selector
        // The first 3 should be found by the primary selectors (base-card, job-search-card, jobs-search-results__list-item)
        XCTAssertGreaterThanOrEqual(jobs.count, 3)
    }

    func testParseJobListingTitles() throws {
        let html = try loadFixture("job_listing")
        let jobs = try JobParser.parseJobSearch(html: html)

        let titles = jobs.map(\.title)
        XCTAssertTrue(titles.contains("Senior iOS Developer"))
        XCTAssertTrue(titles.contains("Backend Engineer"))
        XCTAssertTrue(titles.contains("ML Engineer"))
    }

    func testParseJobListingCompanies() throws {
        let html = try loadFixture("job_listing")
        let jobs = try JobParser.parseJobSearch(html: html)

        let companies = jobs.map(\.company)
        XCTAssertTrue(companies.contains("Apple"))
        XCTAssertTrue(companies.contains("Google"))
        XCTAssertTrue(companies.contains("Meta"))
    }

    func testParseJobListingIDs() throws {
        let html = try loadFixture("job_listing")
        let jobs = try JobParser.parseJobSearch(html: html)

        let ids = jobs.map(\.id)
        XCTAssertTrue(ids.contains("3901234567"))
        XCTAssertTrue(ids.contains("3902345678"))
        XCTAssertTrue(ids.contains("3903456789"))
    }

    func testParseJobListingURLs() throws {
        let html = try loadFixture("job_listing")
        let jobs = try JobParser.parseJobSearch(html: html)

        for job in jobs {
            XCTAssertTrue(job.jobURL.contains("linkedin.com/jobs/view/"))
            XCTAssertTrue(job.jobURL.contains(job.id))
        }
    }

    func testParseJobListingLocations() throws {
        let html = try loadFixture("job_listing")
        let jobs = try JobParser.parseJobSearch(html: html)

        // First job (base-card) has location in .base-search-card__metadata span
        if let appleJob = jobs.first(where: { $0.title == "Senior iOS Developer" }) {
            XCTAssertNotNil(appleJob.location)
            XCTAssertTrue(appleJob.location!.contains("Cupertino"))
        }

        // Second job (job-search-card) has location in .job-search-card__location
        if let googleJob = jobs.first(where: { $0.title == "Backend Engineer" }) {
            XCTAssertNotNil(googleJob.location)
            XCTAssertTrue(googleJob.location!.contains("Mountain View"))
        }
    }

    func testParseJobListingSalary() throws {
        let html = try loadFixture("job_listing")
        let jobs = try JobParser.parseJobSearch(html: html)

        // First job has salary via .base-search-card__salary
        if let appleJob = jobs.first(where: { $0.title == "Senior iOS Developer" }) {
            XCTAssertNotNil(appleJob.salary)
            XCTAssertTrue(appleJob.salary!.contains("180,000"))
        }

        // Second job has salary via .job-search-card__salary-info
        if let googleJob = jobs.first(where: { $0.title == "Backend Engineer" }) {
            XCTAssertNotNil(googleJob.salary)
            XCTAssertTrue(googleJob.salary!.contains("160,000"))
        }
    }

    func testParseJobListingEasyApply() throws {
        let html = try loadFixture("job_listing")
        let jobs = try JobParser.parseJobSearch(html: html)

        // First job has [data-is-easy-apply-job]
        if let appleJob = jobs.first(where: { $0.title == "Senior iOS Developer" }) {
            XCTAssertTrue(appleJob.isEasyApply)
        }

        // Third job has .job-search-card__easy-apply-button
        if let metaJob = jobs.first(where: { $0.title == "ML Engineer" }) {
            XCTAssertTrue(metaJob.isEasyApply)
        }
    }

    func testParseJobListingPostedDate() throws {
        let html = try loadFixture("job_listing")
        let jobs = try JobParser.parseJobSearch(html: html)

        // First job has <time> element
        if let appleJob = jobs.first(where: { $0.title == "Senior iOS Developer" }) {
            XCTAssertNotNil(appleJob.postedDate)
            XCTAssertTrue(appleJob.postedDate!.contains("2 days ago"))
        }

        // Second job has .job-search-card__listdate
        if let googleJob = jobs.first(where: { $0.title == "Backend Engineer" }) {
            XCTAssertNotNil(googleJob.postedDate)
            XCTAssertTrue(googleJob.postedDate!.contains("1 week ago"))
        }
    }

    func testParseJobListingsWithLimit() throws {
        let html = try loadFixture("job_listing")
        let jobs = try JobParser.parseJobSearch(html: html, limit: 2)

        XCTAssertLessThanOrEqual(jobs.count, 2)
    }

    func testParseEmptyJobSearch() throws {
        let html = "<html><body><div class='no-results'>No jobs found</div></body></html>"
        let jobs = try JobParser.parseJobSearch(html: html)

        XCTAssertTrue(jobs.isEmpty)
    }

    // MARK: - Job Details: JSON-LD

    func testParseJobDetailsFromJSONLD() throws {
        let html = try loadFixture("job_details_jsonld")
        let job = try JobParser.parseJobDetails(html: html, jobId: "3901234567")

        XCTAssertEqual(job.id, "3901234567")
        XCTAssertEqual(job.title, "Senior iOS Developer")
        XCTAssertEqual(job.company, "Apple")
        XCTAssertEqual(job.companyURL, "https://www.linkedin.com/company/apple")
        XCTAssertEqual(job.employmentType, "FULL_TIME")
        XCTAssertEqual(job.postedDate, "2024-01-15")
        XCTAssertTrue(job.jobURL.contains("3901234567"))
    }

    func testParseJobDetailsJSONLDLocation() throws {
        let html = try loadFixture("job_details_jsonld")
        let job = try JobParser.parseJobDetails(html: html, jobId: "3901234567")

        XCTAssertNotNil(job.location)
        // JSON-LD location is assembled from addressLocality, addressRegion, addressCountry
        XCTAssertTrue(job.location!.contains("Cupertino"))
        XCTAssertTrue(job.location!.contains("CA"))
        XCTAssertTrue(job.location!.contains("US"))
    }

    func testParseJobDetailsJSONLDSalary() throws {
        let html = try loadFixture("job_details_jsonld")
        let job = try JobParser.parseJobDetails(html: html, jobId: "3901234567")

        XCTAssertNotNil(job.salary)
        XCTAssertTrue(job.salary!.contains("USD"))
        XCTAssertTrue(job.salary!.contains("180000"))
        XCTAssertTrue(job.salary!.contains("250000"))
    }

    func testParseJobDetailsJSONLDDescription() throws {
        let html = try loadFixture("job_details_jsonld")
        let job = try JobParser.parseJobDetails(html: html, jobId: "3901234567")

        XCTAssertNotNil(job.description)
        XCTAssertTrue(job.description!.contains("Senior iOS Developer"))
        XCTAssertTrue(job.description!.contains("Swift"))
    }

    func testParseJobDetailsJSONLDSkills() throws {
        let html = try loadFixture("job_details_jsonld")
        let job = try JobParser.parseJobDetails(html: html, jobId: "3901234567")

        XCTAssertFalse(job.skills.isEmpty)
        XCTAssertTrue(job.skills.contains("Swift"))
        XCTAssertTrue(job.skills.contains("iOS Development"))
        XCTAssertTrue(job.skills.contains("SwiftUI"))
        XCTAssertTrue(job.skills.contains("UIKit"))
        XCTAssertTrue(job.skills.contains("Xcode"))
    }

    func testParseJobDetailsJSONLDWorkplaceType() throws {
        let html = try loadFixture("job_details_jsonld")
        let job = try JobParser.parseJobDetails(html: html, jobId: "3901234567")

        XCTAssertNotNil(job.workplaceType)
        XCTAssertTrue(job.workplaceType!.contains("On-site"))
    }

    func testParseJobDetailsJSONLDExperienceLevel() throws {
        let html = try loadFixture("job_details_jsonld")
        let job = try JobParser.parseJobDetails(html: html, jobId: "3901234567")

        XCTAssertNotNil(job.experienceLevel)
        XCTAssertTrue(job.experienceLevel!.contains("Mid-Senior"))
    }

    func testParseJobDetailsJSONLDApplicantCount() throws {
        let html = try loadFixture("job_details_jsonld")
        let job = try JobParser.parseJobDetails(html: html, jobId: "3901234567")

        XCTAssertNotNil(job.applicantCount)
        XCTAssertTrue(job.applicantCount!.contains("200"))
    }

    func testParseJobDetailsJSONLDEasyApply() throws {
        let html = try loadFixture("job_details_jsonld")
        let job = try JobParser.parseJobDetails(html: html, jobId: "3901234567")

        XCTAssertTrue(job.isEasyApply)
    }

    // MARK: - Job Details: HTML-Only

    func testParseJobDetailsFromHTMLOnly() throws {
        let html = try loadFixture("job_details_html_only")
        let job = try JobParser.parseJobDetails(html: html, jobId: "3902345678")

        XCTAssertEqual(job.id, "3902345678")
        XCTAssertEqual(job.title, "Backend Engineer")
        XCTAssertEqual(job.company, "Google")
        XCTAssertTrue(job.jobURL.contains("3902345678"))
    }

    func testParseJobDetailsHTMLOnlyDescription() throws {
        let html = try loadFixture("job_details_html_only")
        let job = try JobParser.parseJobDetails(html: html, jobId: "3902345678")

        XCTAssertNotNil(job.description)
        XCTAssertTrue(job.description!.contains("backend engineering team"))
        XCTAssertTrue(job.description!.contains("distributed systems"))
    }

    func testParseJobDetailsHTMLOnlyWorkplaceType() throws {
        let html = try loadFixture("job_details_html_only")
        let job = try JobParser.parseJobDetails(html: html, jobId: "3902345678")

        XCTAssertNotNil(job.workplaceType)
        XCTAssertTrue(job.workplaceType!.contains("Hybrid"))
    }

    func testParseJobDetailsHTMLOnlySkills() throws {
        let html = try loadFixture("job_details_html_only")
        let job = try JobParser.parseJobDetails(html: html, jobId: "3902345678")

        XCTAssertFalse(job.skills.isEmpty)
        XCTAssertTrue(job.skills.contains("Go"))
        XCTAssertTrue(job.skills.contains("Distributed Systems"))
        XCTAssertTrue(job.skills.contains("Kubernetes"))
    }

    func testParseJobDetailsHTMLOnlyEasyApply() throws {
        let html = try loadFixture("job_details_html_only")
        let job = try JobParser.parseJobDetails(html: html, jobId: "3902345678")

        XCTAssertTrue(job.isEasyApply)
    }

    func testParseJobDetailsHTMLOnlyApplicantCount() throws {
        let html = try loadFixture("job_details_html_only")
        let job = try JobParser.parseJobDetails(html: html, jobId: "3902345678")

        XCTAssertNotNil(job.applicantCount)
        XCTAssertTrue(job.applicantCount!.contains("25"))
    }

    func testParseJobDetailsHTMLOnlySalary() throws {
        let html = try loadFixture("job_details_html_only")
        let job = try JobParser.parseJobDetails(html: html, jobId: "3902345678")

        XCTAssertNotNil(job.salary)
        XCTAssertTrue(job.salary!.contains("160,000"))
    }

    func testParseJobDetailsHTMLOnlyPostedDate() throws {
        let html = try loadFixture("job_details_html_only")
        let job = try JobParser.parseJobDetails(html: html, jobId: "3902345678")

        XCTAssertNotNil(job.postedDate)
        XCTAssertTrue(job.postedDate!.contains("1 week ago"))
    }

    // MARK: - Job Details: Edge Cases

    func testParseJobWithMissingFields() throws {
        let html = """
        <html><body>
          <h1 class="topcard__title">Mystery Job</h1>
        </body></html>
        """
        let job = try JobParser.parseJobDetails(html: html, jobId: "999")

        XCTAssertEqual(job.id, "999")
        XCTAssertEqual(job.title, "Mystery Job")
        XCTAssertEqual(job.company, "")
        XCTAssertNil(job.location)
        XCTAssertNil(job.workplaceType)
        XCTAssertNil(job.employmentType)
        XCTAssertNil(job.experienceLevel)
        XCTAssertNil(job.salary)
        XCTAssertNil(job.description)
        XCTAssertTrue(job.skills.isEmpty)
        XCTAssertFalse(job.isEasyApply)
    }

    func testParseJobDetailsWithGraphFormatJSONLD() throws {
        let html = """
        <html><head>
        <script type="application/ld+json">
        {
          "@graph": [
            {
              "@type": "JobPosting",
              "title": "Graph Job",
              "hiringOrganization": {"@type": "Organization", "name": "GraphCo", "sameAs": "https://linkedin.com/company/graphco"},
              "jobLocation": {"@type": "Place", "address": {"@type": "PostalAddress", "addressLocality": "Remote"}},
              "employmentType": ["FULL_TIME", "CONTRACT"],
              "description": "A job found in a graph"
            }
          ]
        }
        </script>
        </head><body></body></html>
        """
        let job = try JobParser.parseJobDetails(html: html, jobId: "graph-1")

        XCTAssertEqual(job.title, "Graph Job")
        XCTAssertEqual(job.company, "GraphCo")
        XCTAssertEqual(job.companyURL, "https://linkedin.com/company/graphco")
        XCTAssertNotNil(job.location)
        XCTAssertTrue(job.location!.contains("Remote"))
        // employmentType as array should be joined
        XCTAssertEqual(job.employmentType, "FULL_TIME, CONTRACT")
    }

    func testParseJobDetailsCleanDescription() throws {
        let html = """
        <html><head>
        <script type="application/ld+json">
        {
          "@type": "JobPosting",
          "title": "Test",
          "hiringOrganization": {"name": "Co"},
          "description": "Hello &amp; welcome! This is &lt;bold&gt; and uses &quot;quotes&quot; with &nbsp; spaces"
        }
        </script>
        </head><body></body></html>
        """
        let job = try JobParser.parseJobDetails(html: html, jobId: "clean-1")

        XCTAssertNotNil(job.description)
        // Verify HTML entities are cleaned
        XCTAssertTrue(job.description!.contains("Hello & welcome"))
        XCTAssertTrue(job.description!.contains("<bold>"))
        XCTAssertTrue(job.description!.contains("\"quotes\""))
        XCTAssertFalse(job.description!.contains("&amp;"))
        XCTAssertFalse(job.description!.contains("&lt;"))
        XCTAssertFalse(job.description!.contains("&nbsp;"))
    }

    func testParseJobDetailsWithoutSalary() throws {
        let html = """
        <html><head>
        <script type="application/ld+json">
        {
          "@type": "JobPosting",
          "title": "No Salary Job",
          "hiringOrganization": {"name": "CheapCo"}
        }
        </script>
        </head><body></body></html>
        """
        let job = try JobParser.parseJobDetails(html: html, jobId: "nosalary-1")

        XCTAssertNil(job.salary)
    }

    // MARK: - Helpers

    private func loadFixture(_ name: String) throws -> String {
        let url = Bundle.module.url(forResource: name, withExtension: "html", subdirectory: "Fixtures")!
        return try String(contentsOf: url, encoding: .utf8)
    }
}
