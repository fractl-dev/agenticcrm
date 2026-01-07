module agenticcrm.core

entity CRMConfig {
    id UUID @id @default(uuid()),
    gmailEmail String,
    ownerId String
}

record ContactInfo {
    contactEmail String,
    contactFirstName String,
    contactLastName String,
    meetingTitle String,
    meetingBody String,
    meetingDate String
}

record ContactSearchResult {
    contactFound Boolean,
    existingContactId String @optional
}

record ContactResult {
    finalContactId String
}

record EmailFilterResult {
    shouldProcess Boolean
}

record SkipResult {
    skipped Boolean,
    reason String
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

@public agent filterEmail {
  llm "sonnet_llm",
  role "Extract email information from gmail/Email instance and analyze for CRM processing decisions."
  instruction "You receive a gmail/Email instance from the previous context.

Access the email data from the message that was passed to the flow. The email structure has an 'attributes' field containing:
- sender: string like 'Name <email@domain.com>'
- recipients: string like 'Name <email@domain.com>'
- subject: the email subject line
- body: the email body content
- date: ISO 8601 timestamp

YOUR TASK: Analyze the email context and determine if this should be processed for CRM.

It should be processed if:
- Business discussion with clients/prospects
- Meeting coordination or follow-up
- Onboarding or sales conversation

It shouldn't be processed if:
- Automated sender (contains no-reply, noreply, automated)
- Newsletter (subject has unsubscribe, newsletter, digest)
- System notification or spam

Don't generate markdown format, just invoke the agenticcrm.core/EmailFilterResult and nothing else.",
  responseSchema agenticcrm.core/EmailFilterResult,
  retry classifyRetry
}

decision emailShouldBeProcessed {
  case (shouldProcess == true) {
    ProcessEmail
  }
  case (shouldProcess == false) {
    SkipEmail
  }
}

@public agent parseEmailInfo {
  llm "sonnet_llm",
  role "Extract contact information and meeting details from an email."
    instruction "You have access to the email message from the flow context and you need to figure out who is the contact and owner.

The email in the context is a gmail/Email instance with an 'attributes' field containing:
- sender: string like 'Name <email@domain.com>' or just 'email@domain.com'
- recipients: string like 'Name <email@domain.com>' or just 'email@domain.com'
- subject: the email subject line
- body: the email body content
- date: ISO 8601 timestamp

STEP 1: Extract emails and names from the email attributes in the context
- From sender: extract email address and name (if 'Name <email>' format, extract both; if just 'email', extract firstName and lastName from the name)
- From recipients: same extraction logic

STEP 2: Query the agenticcrm.core/CRMConfig
- Query agenticcrm.core/CRMConfig, you will receive the information about {{gmailEmail}} and {{ownerId}}.

STEP 2: Determine which participant is the CONTACT (not the user):
- If sender email matches {{gmailEmail}}, then the recipient is the contact
- If recipient email matches {{gmailEmail}}, then the sender is the contact
- Extract contactEmail, contactFirstName, contactLastName from the identified contact

STEP 3: Extract meeting details from the email attributes
- meetingTitle: exact value from subject field
- meetingDate: exact value from date field (keep ISO 8601 format)
- meetingBody: summarize the body of email in a descriptive clear structure. If there are action items mentioned, create numbered action items.

STEP 4: Return ContactInfo with ACTUAL extracted values:
- contactEmail, contactFirstName, contactLastName
- meetingTitle, meetingBody, meetingDate

DO NOT return empty strings - extract actual values from the email in the context.
Try to figure out contactFirstName and contactLastName if not provided on sender or recipient from the email body which starts from abbreviation like: Hi, <>",
  responseSchema agenticcrm.core/ContactInfo,
  tools [agenticrm.core/CRMConfig],
  retry classifyRetry
}

@public agent findExistingContact {
  llm "sonnet_llm",
  role "Search for an existing contact in HubSpot by email address."
  instruction "Call agenticcrm.core/FindContactByEmail with the exact email from {{contactEmail}}.

Return the result:
- contactFound: true or false
- existingContactId: the contact ID if found",
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

workflow updateExistingContact {
  {ContactResult {
    finalContactId existingContactId
  }}
}

@public agent createNewContact {
  llm "sonnet_llm",
  role "Create a new contact in HubSpot CRM."
  instruction "Create contact using hubspot/Contact with:
- email from {{contactEmail}}
- first_name from {{contactFirstName}}
- last_name from {{contactLastName}}

Return finalContactId with the id from the created contact.",
  responseSchema agenticcrm.core/ContactResult,
  retry classifyRetry,
  tools [hubspot/Contact]
}

workflow skipProcessing {
  {SkipResult {
    skipped true,
    reason "Email filtered out (automated sender or newsletter)"
  }}
}

@public agent createMeeting {
  llm "sonnet_llm",
  role "Create a meeting record in HubSpot to log the email interaction."
  instruction "Convert {{meetingDate}} from ISO 8601 to Unix milliseconds.
Calculate end time as start + 3600000 (1 hour).

Create meeting using hubspot/Meeting with:
- meeting_title from {{meetingTitle}}
- meeting_body from {{meetingBody}}
- timestamp: Unix milliseconds as string
- meeting_outcome: 'COMPLETED'
- meeting_start_time: Unix milliseconds as string
- meeting_end_time: start + 3600000 as string
- owner from {{ownerId}} (use the ownerId provided)
- associated_contacts from {{finalContactId}} (use the contact ID provided)

All timestamps must be Unix milliseconds as strings.",
  retry classifyRetry,
  tools [hubspot/Meeting]
}

flow crmManager {
  filterEmail --> emailShouldBeProcessed
  emailShouldBeProcessed --> "SkipEmail" skipProcessing
  emailShouldBeProcessed --> "ProcessEmail" parseEmailInfo
  parseEmailInfo --> findExistingContact
  findExistingContact --> contactExistsCheck
  contactExistsCheck --> "ContactExists" updateExistingContact
  contactExistsCheck --> "ContactNotFound" createNewContact
  updateExistingContact --> createMeeting
  createNewContact --> createMeeting
}

@public agent crmManager {
  role "You coordinate the complete CRM workflow: filter the email, extract contact and meeting information, find or create the contact in HubSpot, and create the meeting with proper associations.",
  instruction "You received an email message: {{message}}.

Your task is to execute the crmManager flow with this email:

1. First, initialize the CRM configuration to get gmailEmail and ownerId
2. Filter the email to determine if it should be processed
3. If it should be processed, extract contact and meeting information
4. Find or create the contact in HubSpot
5. Create a meeting record associated with the contact

Execute the flow and ensure the email message context is available to all subsequent agents in the flow. The message should be accessible throughout the entire workflow execution."
}

workflow @after create:gmail/Email {
    {crmManager {message gmail/Email}}
}
