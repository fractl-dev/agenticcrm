module agenticcrm.core

record ContactInfo {
    contactEmail String,
    firstName String,
    lastName String,
    meetingTitle String,
    meetingBody String,
    meetingDate String,
    ownerEmail String
}

record ContactSearchResult {
    contactFound Boolean,
    existingContactId String @optional
}

record ContactResult {
    finalContactId String
}

record OwnerResult {
    ownerId String @optional
}

record EmailFilterResult {
    shouldProcess Boolean,
    reason String
}

record SkipResult {
    skipped Boolean,
    reason String
}

record OwnerCheckResult {
    isOwner Boolean,
    ownerDetails String @optional
}

event FindContactByEmail {
    email String
}

workflow FindContactByEmail {
    {hubspot/Contact {email? FindContactByEmail.email}} @as foundContacts;

    if (foundContacts.length > 0) {
        foundContacts @as [firstContact];
        {ContactSearchResult {
            contactFound true,
            existingContactId firstContact.id
        }}
    } else {
        {ContactSearchResult {
            contactFound false
        }}
    }
}

event FindOwnerByEmail {
    email String
}

workflow FindOwnerByEmail {
    {hubspot/Owner {email? FindOwnerByEmail.email}} @as foundOwners;

    if (foundOwners.length > 0) {
        foundOwners @as [firstOwner];
        {OwnerResult {
            ownerId firstOwner.id
        }}
    } else {
        console.log("WARNING: No owner found for email: " + FindOwnerByEmail.email);
        {OwnerResult {
            ownerId null
        }}
    }
}

@public agent filterEmail {
  llm "llm01",
  role "Determine if an email should be processed for CRM."
  instruction "You have access to {{message}} which contains a gmail/Email instance.

Analyze the email and determine if it should be processed for CRM (creating contacts and meetings).

PROCESS THE EMAIL (return shouldProcess=true) if:
- It's a business communication with a client, prospect, or partner
- It's a meeting discussion or project update with external parties
- It contains actionable business information worth tracking

DO NOT PROCESS (return shouldProcess=false) if:
- It's an automated notification (e.g., 'no-reply@', 'noreply@', 'automated@')
- It's a newsletter or marketing email
- It's a system-generated message
- It's spam or promotional content
- It's an internal team discussion (both sender and recipient are from the same domain)
- The subject contains: 'unsubscribe', 'newsletter', 'notification', 'alert', 'digest'

Analyze the sender, subject, and body to make your decision.

Return JSON:
{
  \"shouldProcess\": true or false,
  \"reason\": \"Brief explanation of why it should or should not be processed\"
}",
  responseSchema agenticcrm.core/EmailFilterResult,
  retry classifyRetry
}

@public agent checkIfOwner {
  llm "llm01",
  role "Check if contact email belongs to an owner."
  instruction "Query hubspot/Owner with email={{contactEmail}}.
If owner found, return {\"isOwner\": true, \"ownerDetails\": \"Owner: <name>\"}.
If no owner found, return {\"isOwner\": false}.",
  responseSchema agenticcrm.core/OwnerCheckResult,
  retry classifyRetry,
  tools [hubspot/Owner]
}

@public agent parseEmailInfo {
  llm "llm01",
  role "Extract contact and meeting information from the gmail/Email instance."
  instruction "You have access to {{message}} which contains a gmail/Email instance.

The {{message}} structure is a JSON object with an 'attributes' field containing:
- sender: string like 'Name <email@domain.com>'
- recipients: string like 'Name <email@domain.com>'
- subject: the email subject line
- body: the email body content
- date: ISO 8601 timestamp

YOUR TASK: Parse {{message}} and extract the following information:

STEP 1: Find sender and recipients
From {{message}}, locate the sender field and recipients field.
Example: if sender is 'Admin User <admin@company.com>', that's the sender text.

STEP 2: Determine which contact to extract (based on admin email)
Check if sender or recipients contains the admin email (usually from your organization's domain).
IF sender contains your admin/owner email THEN use recipients for contact extraction
ELSE use sender for contact extraction

STEP 3: Extract contact information from chosen text
From the chosen text (sender or recipients):
- contactEmail = extract EXACTLY the email address between < and >
- firstName = extract the first word before <
- lastName = extract the second word before <

STEP 4: Extract meeting title
meetingTitle = copy the EXACT value from the subject field in {{message}}

STEP 5: Extract action items and key discussion points
Read the body field from {{message}} and identify:
- Action items mentioned (tasks, to-dos, requests)
- Key decisions or discussion points
- Important deadlines or next steps
- Questions that need answers

Create a concise summary focusing on these actionable elements.
meetingBody = summary of action items and key discussion points from the email

STEP 6: Extract meeting date
meetingDate = copy the EXACT value from the date field in {{message}}

STEP 7: Extract owner email
Determine the owner email (the admin/organizer of the meeting):
- IF sender is from your organization's domain THEN ownerEmail = extract email from sender (between < and >)
- ELSE IF recipients is from your organization's domain THEN ownerEmail = extract email from recipients (between < and >)
- ELSE ownerEmail = extract email from sender (between < and >)
The owner is typically the person from your organization who is managing the meeting.

CRITICAL RULES:
- Parse the actual {{message}} you receive, not examples
- Email addresses must be copied EXACTLY as they appear between < and >
- Do NOT modify domains or email addresses
- The date must be copied EXACTLY in ISO 8601 format
- All data comes from {{message}}, not from your knowledge

EXAMPLE 1 (sender is from your organization):
If {{message}} contains:
{
  \"attributes\": {
    \"sender\": \"Sales Rep <sales@yourcompany.com>\",
    \"recipients\": \"John Smith <john@clientcompany.com>\",
    \"subject\": \"Q1 Planning Discussion\",
    \"body\": \"Hi John, let's schedule time to review Q1 goals. Please send me your team's priorities by Friday. We also need to finalize the budget allocation.\",
    \"date\": \"2025-12-31T10:30:00.000Z\"
  }
}

You would extract:
{
  \"contactEmail\": \"john@clientcompany.com\",
  \"firstName\": \"John\",
  \"lastName\": \"Smith\",
  \"meetingTitle\": \"Q1 Planning Discussion\",
  \"meetingBody\": \"Action items: John to send team priorities by Friday. Need to finalize budget allocation. Schedule meeting to review Q1 goals.\",
  \"meetingDate\": \"2025-12-31T10:30:00.000Z\",
  \"ownerEmail\": \"sales@yourcompany.com\"
}

EXAMPLE 2 (recipient is from your organization):
If {{message}} contains:
{
  \"attributes\": {
    \"sender\": \"Jane Doe <jane@externalcorp.io>\",
    \"recipients\": \"Account Manager <am@yourcompany.com>\",
    \"subject\": \"Partnership Proposal\",
    \"body\": \"Hi, I'd like to discuss a potential partnership. Can we set up a call next week? I'll prepare a deck outlining our proposal and revenue share model.\",
    \"date\": \"2025-12-31T14:00:00.000Z\"
  }
}

You would extract:
{
  \"contactEmail\": \"jane@externalcorp.io\",
  \"firstName\": \"Jane\",
  \"lastName\": \"Doe\",
  \"meetingTitle\": \"Partnership Proposal\",
  \"meetingBody\": \"Action items: Schedule call for next week. Jane to prepare proposal deck covering revenue share model. Discuss partnership opportunity.\",
  \"meetingDate\": \"2025-12-31T14:00:00.000Z\",
  \"ownerEmail\": \"am@yourcompany.com\"
}",
  responseSchema agenticcrm.core/ContactInfo,
  retry classifyRetry
}

@public agent findExistingContact {
  llm "llm01",
  role "Search for contact in HubSpot."
  instruction "You have available from the scratchpad: {{contactEmail}}

STEP 1: Extract the contact email
Read {{contactEmail}} from the scratchpad.
This is the email address to search for (e.g., 'john@clientcompany.com').

STEP 2: Call the FindContactByEmail tool
Use the tool agenticcrm.core/FindContactByEmail
Pass the parameter: email = {{contactEmail}}
Use the EXACT email value - do not modify it.

STEP 3: Return the result
The tool will return a ContactSearchResult object with:
- contactFound: true or false
- existingContactId: the contact ID (if found)

Return exactly what the tool provides in this JSON format:
{
  \"contactFound\": true or false,
  \"existingContactId\": \"the id value\" (only if found)
}

EXAMPLE:
If {{contactEmail}} = 'john@clientcompany.com'
You call: agenticcrm.core/FindContactByEmail with email='john@clientcompany.com'
Tool returns: ContactSearchResult with contactFound=true, existingContactId='123456789'
You return: {\"contactFound\": true, \"existingContactId\": \"123456789\"}

CRITICAL RULES:
- Use the EXACT email from {{contactEmail}}
- Do not modify the email address
- Return the exact structure the tool provides",
  responseSchema agenticcrm.core/ContactSearchResult,
  retry classifyRetry,
  tools [agenticcrm.core/FindContactByEmail]
}

decision contactExistsCheck {
  case (contactFound == true) {
    ContactExists
  }
  case (contactFound == false) {
    ContactNotFound
  }
}

@public agent updateExistingContact {
  llm "llm01",
  role "Return the existing contact ID."
  instruction "You have available from the scratchpad: {{existingContactId}}

STEP 1: Extract the existing contact ID
Read {{existingContactId}} from the scratchpad.
This is the HubSpot contact ID that was found (e.g., '123456789').

STEP 2: Return the result
Return this exact JSON structure:
{
  \"finalContactId\": \"<the contact ID value>\"
}

EXAMPLE:
If {{existingContactId}} = '123456789'
You return: {\"finalContactId\": \"123456789\"}

CRITICAL RULES:
- Use the EXACT value from {{existingContactId}}
- Do not modify the ID
- The ID must be a string",
  responseSchema agenticcrm.core/ContactResult,
  retry classifyRetry,
  tools [hubspot/Contact]
}

@public agent createNewContact {
  llm "llm01",
  role "Create a new contact in HubSpot."
  instruction "You have available from the scratchpad:
- {{contactEmail}} - the email address
- {{firstName}} - the first name
- {{lastName}} - the last name

STEP 1: Extract contact information from scratchpad
Read these values:
- contactEmail from {{contactEmail}}
- firstName from {{firstName}}
- lastName from {{lastName}}

STEP 2: Create the contact in HubSpot
Use the hubspot/Contact tool to create a contact with:
- email: the EXACT value from {{contactEmail}}
- first_name: the EXACT value from {{firstName}}
- last_name: the EXACT value from {{lastName}}

STEP 3: Extract and return the ID
The tool returns an object with an id field.
Extract that id value and return:
{\"finalContactId\": \"<the id value>\"}

EXAMPLE:
If {{contactEmail}}='john@clientcompany.com', {{firstName}}='John', {{lastName}}='Smith'
You call hubspot/Contact to create the contact
Tool returns: {id: '123456789', ...}
You return: {\"finalContactId\": \"123456789\"}

CRITICAL GUARDRAILS:
- Use the EXACT email from {{contactEmail}} - do not change the domain
- Use the EXACT firstName from {{firstName}} - do not modify it
- Use the EXACT lastName from {{lastName}} - do not modify it
- Extract the id field from the tool response correctly",
  responseSchema agenticcrm.core/ContactResult,
  retry classifyRetry,
  tools [hubspot/Contact]
}

decision emailShouldBeProcessed {
  case (shouldProcess == true) {
    ProcessEmail
  }
  case (shouldProcess == false) {
    SkipEmail
  }
}

decision contactIsOwner {
  case (isOwner == true) {
    SkipContactCreation
  }
  case (isOwner == false) {
    ProceedWithContact
  }
}

workflow findOwner {
  {agenticcrm.core/FindOwnerByEmail {email ownerEmail}}
}

@public agent skipProcessing {
  llm "llm01",
  role "Return skip status when email is not processed."
  instruction "The email was filtered out and will not be processed.
Use the reason from {{reason}}.

Return JSON:
{
  \"skipped\": true,
  \"reason\": <use the exact value from {{reason}}>
}",
  responseSchema agenticcrm.core/SkipResult,
  retry classifyRetry
}

@public agent skipOwnerContact {
  llm "llm01",
  role "Skip contact creation for owners and proceed to meeting."
  instruction "The contact email belongs to an owner, so we skip contact creation.
Return the owner details to use directly.

Return JSON with just a note that contact creation was skipped:
{
  \"finalContactId\": null
}

Note: This will proceed to meeting creation without a contact association.",
  responseSchema agenticcrm.core/ContactResult,
  retry classifyRetry
}

@public agent createMeeting {
  llm "llm01",
  role "Create a meeting in HubSpot with all required fields."
  instruction "Create a meeting in HubSpot using the hubspot/Meeting tool.

YOU HAVE AVAILABLE:
- {{finalContactId}} - the contact ID to associate (string like \"123456789\")
- {{meetingTitle}} - the meeting title (string)
- {{meetingBody}} - the meeting summary (string)
- {{meetingDate}} - the email date in ISO 8601 format (e.g., '2025-12-31T05:02:35.000Z')
- {{ownerId}} - the owner ID (may be null or a string like \"987654321\")

STEP 1: Extract owner ID
Read {{ownerId}} from the scratchpad.
Use the exact value from {{ownerId}} as the owner ID.
If it's null or empty, pass null to the owner field.

STEP 2: Extract contact ID
Read {{finalContactId}} from the scratchpad.
If finalContactId is null (contact was an owner), do NOT include associated_contacts field.
If finalContactId has a value, use this EXACT value for associated_contacts.

STEP 3: Convert email date to Unix timestamp
Take the ISO 8601 date from {{meetingDate}} (e.g., '2025-12-31T05:02:35.000Z')
Convert it to Unix timestamp in milliseconds.
Example: '2025-12-31T05:02:35.000Z' converts to 1735620155000

STEP 4: Calculate end time
Add 3600000 milliseconds (1 hour) to the timestamp.
Example: 1735620155000 + 3600000 = 1735623755000

STEP 5: Use the hubspot/Meeting tool with ALL these fields:
- meeting_title: EXACT value from {{meetingTitle}}
- meeting_body: EXACT value from {{meetingBody}}
- timestamp: the Unix milliseconds timestamp from the email date (as string)
- meeting_outcome: exactly \"COMPLETED\"
- meeting_start_time: the Unix milliseconds timestamp from the email date (as string)
- meeting_end_time: the timestamp + 3600000 (as string)
- owner: the owner ID from STEP 1 (as string)
- associated_contacts: EXACT value from {{finalContactId}} from STEP 2 (as string)

EXAMPLE:
Input values:
- meetingTitle = \"Q1 Planning Discussion\"
- meetingBody = \"Review of quarterly goals and action items\"
- meetingDate = \"2025-12-31T10:30:00.000Z\"
- finalContactId = \"123456789\"
- ownerId = \"987654321\"
- Converted timestamp = 1735646400000

You call the hubspot/Meeting tool with:
{
  \"meeting_title\": \"Q1 Planning Discussion\",
  \"meeting_body\": \"Review of quarterly goals and action items\",
  \"timestamp\": \"1735646400000\",
  \"meeting_outcome\": \"COMPLETED\",
  \"meeting_start_time\": \"1735646400000\",
  \"meeting_end_time\": \"1735650000000\",
  \"owner\": \"987654321\",
  \"associated_contacts\": \"123456789\"
}

CRITICAL GUARDRAILS:
- Convert the ISO 8601 date from {{meetingDate}} to Unix milliseconds
- Use EXACT values from scratchpad variables - do not modify
- All timestamps must be Unix milliseconds as strings
- If ownerId is null, pass null to the owner field (do NOT use a hardcoded fallback)
- If finalContactId is null, omit the associated_contacts field entirely
- If finalContactId has a value, the associated_contacts field MUST be the exact contact ID
- All field values must be strings (except null values)",
  retry classifyRetry,
  tools [hubspot/Meeting]
}

flow crmManager {
  filterEmail --> emailShouldBeProcessed
  emailShouldBeProcessed --> "SkipEmail" skipProcessing
  emailShouldBeProcessed --> "ProcessEmail" parseEmailInfo
  parseEmailInfo --> checkIfOwner
  checkIfOwner --> contactIsOwner
  contactIsOwner --> "SkipContactCreation" skipOwnerContact
  contactIsOwner --> "ProceedWithContact" findExistingContact
  findExistingContact --> contactExistsCheck
  contactExistsCheck --> "ContactExists" updateExistingContact
  contactExistsCheck --> "ContactNotFound" createNewContact
  skipOwnerContact --> findOwner
  updateExistingContact --> findOwner
  createNewContact --> findOwner
  findOwner --> createMeeting
}

@public agent crmManager {
  role "You coordinate the complete CRM workflow: extract contact and meeting information from the email, find or create the contact in HubSpot, find the owner, and create the meeting with proper associations."
}

workflow @after create:gmail/Email {
    {crmManager {message gmail/Email}}
}
