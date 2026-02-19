import XCTest
@testable import LinkLion

final class ProfileParserTests: XCTestCase {

    // MARK: - Person Profile: JSON-LD Tests

    func testParsePersonProfileFromJSONLD() throws {
        let html = try loadFixture("profile_jsonld")
        let profile = try ProfileParser.parsePersonProfile(html: html, username: "johndoe")

        // Basic fields from JSON-LD
        XCTAssertEqual(profile.username, "johndoe")
        XCTAssertEqual(profile.name, "John Doe")
        XCTAssertEqual(profile.jobTitle, "Senior Software Engineer")
        XCTAssertEqual(profile.company, "Acme Corp")
        XCTAssertEqual(profile.location, "San Francisco, California")
        XCTAssertEqual(profile.profileImageURL, "https://media.licdn.com/dms/image/test/photo.jpg")

        // Headline from HTML (.text-body-medium.break-words)
        XCTAssertEqual(profile.headline, "Senior Software Engineer at Acme Corp")

        // About from HTML (#about ~ .display-flex .inline-show-more-text)
        XCTAssertNotNil(profile.about)
        XCTAssertTrue(profile.about!.contains("Passionate about building great software"))
    }

    func testParseExperiencesFromJSONLD() throws {
        let html = try loadFixture("profile_jsonld")
        let profile = try ProfileParser.parsePersonProfile(html: html, username: "johndoe")

        XCTAssertEqual(profile.experiences.count, 2)

        let first = profile.experiences[0]
        XCTAssertEqual(first.title, "Senior Software Engineer")
        XCTAssertEqual(first.company, "Acme Corp")
        XCTAssertEqual(first.startDate, "Jan 2020")
        XCTAssertEqual(first.endDate, "Present")
        XCTAssertEqual(first.duration, "4 yrs")
        XCTAssertNotNil(first.description)
        XCTAssertTrue(first.description!.contains("Led iOS team"))

        let second = profile.experiences[1]
        XCTAssertEqual(second.title, "Software Engineer")
        XCTAssertEqual(second.company, "StartupCo")
        XCTAssertEqual(second.startDate, "Jun 2017")
        XCTAssertEqual(second.endDate, "Dec 2019")
        XCTAssertEqual(second.duration, "2 yrs 7 mos")
    }

    func testParseEducationsFromJSONLD() throws {
        let html = try loadFixture("profile_jsonld")
        let profile = try ProfileParser.parsePersonProfile(html: html, username: "johndoe")

        XCTAssertEqual(profile.educations.count, 1)

        let edu = profile.educations[0]
        XCTAssertEqual(edu.institution, "MIT")
        XCTAssertEqual(edu.degree, "BS Computer Science")
        XCTAssertEqual(edu.startDate, "2013")
        XCTAssertEqual(edu.endDate, "2017")
    }

    func testParseSkillsFromJSONLD() throws {
        let html = try loadFixture("profile_jsonld")
        let profile = try ProfileParser.parsePersonProfile(html: html, username: "johndoe")

        XCTAssertEqual(profile.skills.count, 4)
        XCTAssertTrue(profile.skills.contains("Swift"))
        XCTAssertTrue(profile.skills.contains("iOS Development"))
        XCTAssertTrue(profile.skills.contains("Machine Learning"))
        XCTAssertTrue(profile.skills.contains("Python"))
    }

    func testParseConnectionCountFromJSONLD() throws {
        let html = try loadFixture("profile_jsonld")
        let profile = try ProfileParser.parsePersonProfile(html: html, username: "johndoe")

        XCTAssertNotNil(profile.connectionCount)
        XCTAssertTrue(profile.connectionCount!.contains("500+"))
        XCTAssertTrue(profile.connectionCount!.contains("connections"))
    }

    func testParseFollowerCountFromJSONLD() throws {
        let html = try loadFixture("profile_jsonld")
        let profile = try ProfileParser.parsePersonProfile(html: html, username: "johndoe")

        XCTAssertNotNil(profile.followerCount)
        XCTAssertTrue(profile.followerCount!.contains("1,234"))
        XCTAssertTrue(profile.followerCount!.contains("followers"))
    }

    func testParsePersonProfileNotOpenToWork() throws {
        let html = try loadFixture("profile_jsonld")
        let profile = try ProfileParser.parsePersonProfile(html: html, username: "johndoe")

        XCTAssertFalse(profile.openToWork)
    }

    // MARK: - Person Profile: HTML-Only Tests

    func testParsePersonProfileFromHTMLOnly() throws {
        let html = try loadFixture("profile_html_only")
        let profile = try ProfileParser.parsePersonProfile(html: html, username: "janesmith")

        XCTAssertEqual(profile.username, "janesmith")
        XCTAssertEqual(profile.name, "Jane Smith")
        XCTAssertEqual(profile.headline, "Product Manager at TechGiant")
        XCTAssertEqual(profile.location, "Seattle, Washington")

        // Company/jobTitle extracted from headline "... at ..."
        XCTAssertEqual(profile.jobTitle, "Product Manager")
        XCTAssertEqual(profile.company, "TechGiant")

        XCTAssertNotNil(profile.about)
        XCTAssertTrue(profile.about!.contains("user-centric products"))

        // No JSON-LD, so no profileImageURL
        XCTAssertNil(profile.profileImageURL)
    }

    func testParseExperiencesFromHTMLOnly() throws {
        let html = try loadFixture("profile_html_only")
        let profile = try ProfileParser.parsePersonProfile(html: html, username: "janesmith")

        XCTAssertEqual(profile.experiences.count, 3)
        XCTAssertEqual(profile.experiences[0].title, "Senior Product Manager")
        XCTAssertEqual(profile.experiences[0].company, "TechGiant")
        XCTAssertEqual(profile.experiences[1].title, "Product Manager")
        XCTAssertEqual(profile.experiences[1].company, "MidCo")
        XCTAssertEqual(profile.experiences[2].title, "Associate PM")
        XCTAssertEqual(profile.experiences[2].company, "StartupX")
    }

    func testParseEducationsFromHTMLOnly() throws {
        let html = try loadFixture("profile_html_only")
        let profile = try ProfileParser.parsePersonProfile(html: html, username: "janesmith")

        XCTAssertEqual(profile.educations.count, 2)
        XCTAssertEqual(profile.educations[0].institution, "Stanford University")
        XCTAssertEqual(profile.educations[0].degree, "MBA, Business Administration")
        XCTAssertEqual(profile.educations[1].institution, "UC Berkeley")
        XCTAssertEqual(profile.educations[1].degree, "BS, Computer Science")
    }

    func testParseSkillsFromHTMLOnly() throws {
        let html = try loadFixture("profile_html_only")
        let profile = try ProfileParser.parsePersonProfile(html: html, username: "janesmith")

        XCTAssertEqual(profile.skills.count, 3)
        XCTAssertTrue(profile.skills.contains("Product Management"))
        XCTAssertTrue(profile.skills.contains("Agile Methodologies"))
        XCTAssertTrue(profile.skills.contains("User Research"))
    }

    func testParseConnectionCountFromHTMLOnly() throws {
        let html = try loadFixture("profile_html_only")
        let profile = try ProfileParser.parsePersonProfile(html: html, username: "janesmith")

        XCTAssertNotNil(profile.connectionCount)
        XCTAssertTrue(profile.connectionCount!.contains("connections"))
    }

    func testParseFollowerCountFromHTMLOnly() throws {
        let html = try loadFixture("profile_html_only")
        let profile = try ProfileParser.parsePersonProfile(html: html, username: "janesmith")

        XCTAssertNotNil(profile.followerCount)
        XCTAssertTrue(profile.followerCount!.contains("followers"))
    }

    // MARK: - Person Profile: Minimal Data

    func testParsePersonProfileMinimalData() throws {
        let html = try loadFixture("profile_minimal")
        let profile = try ProfileParser.parsePersonProfile(html: html, username: "alexmin")

        XCTAssertEqual(profile.username, "alexmin")
        XCTAssertEqual(profile.name, "Alex Minimal")
        XCTAssertEqual(profile.headline, "Student")
        XCTAssertNil(profile.about)
        XCTAssertNil(profile.location)
        XCTAssertTrue(profile.experiences.isEmpty)
        XCTAssertTrue(profile.educations.isEmpty)
        XCTAssertTrue(profile.skills.isEmpty)
        XCTAssertNil(profile.profileImageURL)
        XCTAssertNil(profile.connectionCount)
        XCTAssertNil(profile.followerCount)
        XCTAssertFalse(profile.openToWork)
    }

    // MARK: - Person Profile: Open to Work

    func testParsePersonProfileOpenToWork() throws {
        let html = try loadFixture("profile_open_to_work")
        let profile = try ProfileParser.parsePersonProfile(html: html, username: "mariaopentowork")

        XCTAssertEqual(profile.name, "Maria OpenToWork")
        XCTAssertTrue(profile.openToWork)
        XCTAssertTrue(profile.headline!.contains("Full Stack Developer"))
    }

    func testParseOpenToWorkExperiences() throws {
        let html = try loadFixture("profile_open_to_work")
        let profile = try ProfileParser.parsePersonProfile(html: html, username: "mariaopentowork")

        XCTAssertEqual(profile.experiences.count, 1)
        XCTAssertEqual(profile.experiences[0].title, "Full Stack Developer")
        XCTAssertEqual(profile.experiences[0].company, "PreviousJob Inc")
    }

    func testParseOpenToWorkSkills() throws {
        let html = try loadFixture("profile_open_to_work")
        let profile = try ProfileParser.parsePersonProfile(html: html, username: "mariaopentowork")

        XCTAssertEqual(profile.skills.count, 4)
        XCTAssertTrue(profile.skills.contains("React"))
        XCTAssertTrue(profile.skills.contains("Node.js"))
        XCTAssertTrue(profile.skills.contains("TypeScript"))
        XCTAssertTrue(profile.skills.contains("PostgreSQL"))
    }

    // MARK: - Person Profile: Empty HTML

    func testParseEmptyHTML() throws {
        let html = "<html><body></body></html>"
        let profile = try ProfileParser.parsePersonProfile(html: html, username: "empty")

        XCTAssertEqual(profile.username, "empty")
        // Name falls back to username when no h1 or title
        XCTAssertEqual(profile.name, "empty")
        XCTAssertNil(profile.headline)
        XCTAssertNil(profile.about)
        XCTAssertNil(profile.location)
        XCTAssertNil(profile.company)
        XCTAssertNil(profile.jobTitle)
        XCTAssertTrue(profile.experiences.isEmpty)
        XCTAssertTrue(profile.educations.isEmpty)
        XCTAssertTrue(profile.skills.isEmpty)
        XCTAssertNil(profile.profileImageURL)
        XCTAssertNil(profile.connectionCount)
        XCTAssertNil(profile.followerCount)
        XCTAssertFalse(profile.openToWork)
    }

    // MARK: - Person Profile: Job Title/Company Fallback

    func testHTMLOnlyCompanyFromFirstExperience() throws {
        // When headline doesn't contain "at", company/jobTitle come from first experience
        let html = """
        <html><body>
          <h1>Bob Builder</h1>
          <div class="text-body-medium break-words">Passionate builder of things</div>
          <section id="experience"><div><ul>
            <li class="artdeco-list__item">
              <div class="t-bold"><span aria-hidden="true">Construction Lead</span></div>
              <div class="t-normal"><span aria-hidden="true">BuildIt Corp</span></div>
              <div class="t-black--light"><span aria-hidden="true">Jan 2022 - Present · 2 yrs</span></div>
            </li>
          </ul></div></section>
        </body></html>
        """
        let profile = try ProfileParser.parsePersonProfile(html: html, username: "bobbuilder")

        XCTAssertEqual(profile.headline, "Passionate builder of things")
        // Headline doesn't contain " at ", so falls back to first experience
        XCTAssertEqual(profile.company, "BuildIt Corp")
        XCTAssertEqual(profile.jobTitle, "Construction Lead")
    }

    // MARK: - Company Profile: JSON-LD Tests

    func testParseCompanyProfileFromJSONLD() throws {
        let html = try loadFixture("company_jsonld")
        let profile = try ProfileParser.parseCompanyProfile(html: html, companyName: "acme-corp")

        XCTAssertEqual(profile.name, "Acme Corp")
        XCTAssertEqual(profile.slug, "acme-corp")
        XCTAssertNotNil(profile.about)
        XCTAssertTrue(profile.about!.contains("leading technology company"))
        XCTAssertEqual(profile.website, "https://www.acmecorp.com")
        XCTAssertEqual(profile.headquarters, "San Francisco, California")
        XCTAssertEqual(profile.logoURL, "https://media.licdn.com/dms/image/acme/logo.jpg")
    }

    func testParseCompanyDetailsFromJSONLD() throws {
        let html = try loadFixture("company_jsonld")
        let profile = try ProfileParser.parseCompanyProfile(html: html, companyName: "acme-corp")

        XCTAssertEqual(profile.tagline, "Enterprise Technology Solutions")
        XCTAssertEqual(profile.industry, "Technology, Information and Internet")
        XCTAssertEqual(profile.companySize, "1,001-5,000 employees")
        XCTAssertEqual(profile.founded, "2010")
        XCTAssertFalse(profile.specialties.isEmpty)
        XCTAssertTrue(profile.specialties.contains("Cloud Computing"))
        XCTAssertTrue(profile.specialties.contains("Enterprise Software"))
        XCTAssertTrue(profile.specialties.contains("AI/ML"))
        XCTAssertTrue(profile.specialties.contains("DevOps"))
    }

    func testParseCompanyEmployeeCount() throws {
        let html = try loadFixture("company_jsonld")
        let profile = try ProfileParser.parseCompanyProfile(html: html, companyName: "acme-corp")

        XCTAssertNotNil(profile.employeeCount)
        XCTAssertTrue(profile.employeeCount!.contains("employees"))
    }

    func testParseCompanyFollowerCount() throws {
        let html = try loadFixture("company_jsonld")
        let profile = try ProfileParser.parseCompanyProfile(html: html, companyName: "acme-corp")

        XCTAssertNotNil(profile.followerCount)
        XCTAssertTrue(profile.followerCount!.contains("followers"))
    }

    // MARK: - Company Profile: HTML-Only Tests

    func testParseCompanyProfileFromHTMLOnly() throws {
        let html = try loadFixture("company_html_only")
        let profile = try ProfileParser.parseCompanyProfile(html: html, companyName: "startupco")

        XCTAssertEqual(profile.name, "StartupCo")
        XCTAssertEqual(profile.slug, "startupco")
        XCTAssertEqual(profile.tagline, "Building the future of work")
        XCTAssertNotNil(profile.about)
        XCTAssertTrue(profile.about!.contains("reimagining how teams collaborate"))
        XCTAssertEqual(profile.website, "https://www.startupco.io")
        XCTAssertEqual(profile.industry, "Software Development")
        XCTAssertEqual(profile.companySize, "11-50 employees")
        XCTAssertEqual(profile.founded, "2022")
        XCTAssertTrue(profile.specialties.contains("AI"))
        XCTAssertTrue(profile.specialties.contains("Collaboration Tools"))
        XCTAssertTrue(profile.specialties.contains("SaaS"))
    }

    func testParseCompanyHTMLOnlyEmployeeAndFollower() throws {
        let html = try loadFixture("company_html_only")
        let profile = try ProfileParser.parseCompanyProfile(html: html, companyName: "startupco")

        XCTAssertNotNil(profile.employeeCount)
        XCTAssertTrue(profile.employeeCount!.contains("employees"))
        XCTAssertNotNil(profile.followerCount)
        XCTAssertTrue(profile.followerCount!.contains("followers"))
    }

    // MARK: - Company Profile: Minimal Data

    func testParseCompanyMinimalData() throws {
        let html = try loadFixture("company_minimal")
        let profile = try ProfileParser.parseCompanyProfile(html: html, companyName: "tinystartup")

        XCTAssertEqual(profile.name, "TinyStartup")
        XCTAssertEqual(profile.slug, "tinystartup")
        XCTAssertNil(profile.about)
        XCTAssertNil(profile.website)
        XCTAssertNil(profile.industry)
        XCTAssertNil(profile.companySize)
        XCTAssertNil(profile.headquarters)
        XCTAssertNil(profile.founded)
        XCTAssertTrue(profile.specialties.isEmpty)
        XCTAssertNil(profile.employeeCount)
        XCTAssertNil(profile.followerCount)
        XCTAssertNil(profile.logoURL)
    }

    // MARK: - Edge Cases

    func testParseProfileWithGraphFormatJSONLD() throws {
        let html = """
        <html><head>
        <script type="application/ld+json">
        {
          "@context": "https://schema.org",
          "@graph": [
            {
              "@type": "Person",
              "name": "Graph Person",
              "jobTitle": "Data Scientist",
              "worksFor": {"@type": "Organization", "name": "DataCo"},
              "address": {"@type": "PostalAddress", "addressLocality": "Berlin, Germany"},
              "image": {"@type": "ImageObject", "contentUrl": "https://example.com/photo.jpg"}
            }
          ]
        }
        </script>
        </head><body><h1>Graph Person</h1></body></html>
        """
        let profile = try ProfileParser.parsePersonProfile(html: html, username: "graphperson")

        XCTAssertEqual(profile.name, "Graph Person")
        XCTAssertEqual(profile.jobTitle, "Data Scientist")
        XCTAssertEqual(profile.company, "DataCo")
        XCTAssertEqual(profile.location, "Berlin, Germany")
        XCTAssertEqual(profile.profileImageURL, "https://example.com/photo.jpg")
    }

    func testParseProfileWithArrayJobTitle() throws {
        // jobTitle can be an array of strings per the parser
        let html = """
        <html><head>
        <script type="application/ld+json">
        {
          "@type": "Person",
          "name": "Multi Title",
          "jobTitle": ["CTO", "Co-Founder"]
        }
        </script>
        </head><body></body></html>
        """
        let profile = try ProfileParser.parsePersonProfile(html: html, username: "multititle")

        XCTAssertEqual(profile.name, "Multi Title")
        // Parser takes the first from the array
        XCTAssertEqual(profile.jobTitle, "CTO")
    }

    func testParseCompanyWithGraphFormatJSONLD() throws {
        let html = """
        <html><head>
        <script type="application/ld+json">
        {
          "@graph": [
            {
              "@type": "Organization",
              "name": "Graph Corp",
              "description": "A graph-based company",
              "url": "https://graphcorp.com",
              "logo": "https://graphcorp.com/logo.png",
              "address": {"@type": "PostalAddress", "addressLocality": "London, UK"}
            }
          ]
        }
        </script>
        </head><body><h1>Graph Corp</h1></body></html>
        """
        let profile = try ProfileParser.parseCompanyProfile(html: html, companyName: "graph-corp")

        XCTAssertEqual(profile.name, "Graph Corp")
        XCTAssertEqual(profile.about, "A graph-based company")
        XCTAssertEqual(profile.website, "https://graphcorp.com")
        XCTAssertEqual(profile.headquarters, "London, UK")
        // logo as plain string
        XCTAssertEqual(profile.logoURL, "https://graphcorp.com/logo.png")
    }

    func testParseProfileNameFromTitle() throws {
        // When no h1, falls back to title
        let html = """
        <html><head><title>Alice Wonder | LinkedIn</title></head><body></body></html>
        """
        let profile = try ProfileParser.parsePersonProfile(html: html, username: "alicewonder")

        XCTAssertEqual(profile.name, "Alice Wonder")
    }

    // MARK: - Helpers

    private func loadFixture(_ name: String) throws -> String {
        let url = Bundle.module.url(forResource: name, withExtension: "html", subdirectory: "Fixtures")!
        return try String(contentsOf: url, encoding: .utf8)
    }
}
