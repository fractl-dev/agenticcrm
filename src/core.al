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
    shouldProcess Boolean,
    gmailOwnerEmail String @optional,
    hubspotOwnerId String @optional,
    emailSender String @optional,
    emailRecipients String @optional,
    emailSubject String @optional,
    emailBody String @optional,
    emailDate String @optional,
    emailThreadId String @optional
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

event createHubspotContact {
    email String,
    firstName String,
    lastName String
}

workflow createHubspotContact {
    {hubspot/Contact {
        email createHubspotContact.email,
        first_name createHubspotContact.firstName,
        last_name createHubspotContact.lastName
    }} @as contact;

    contact
}

@public agent filterEmail {
  llm "sonnet_llm",
  role "Understand email and analyze for CRM processing decisions.",
  instruction "You receive a complete message about an email and also, receive information about gmail email owner and hubspot owner id.

Access the email data from the message that was passed to the flow. The email contains
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

IMPORTANT: You must return in this format with proper data extracted.
if it should be processed.
{
 \"shouldProcess\": true,
 \"gmailOwnerEmail\": gmail_main_owner_email,
 \"hubspotOwnerId\": hubspot_owner_id,
 \"emailSender\": sender,
 \"emailRecipients\": recipients,
 \"emailSubject\": subject,
 \"emailBody\": body,
 \"emailDate\": date,
 \"emailThreadId\": thread_id
}

else, if it shouldn't be processed, then,
{
 \"shouldProcess\": false
}

Don't generate markdown format, just invoke the agenticcrm.core/EmailFilterResult and nothing else.

CRITICAL OUTPUT FORMAT RULES:
- NEVER wrap your response in markdown code blocks (``` or ``)
- NEVER use markdown formatting in your response
- NEVER add JSON formatting with backticks
- Do NOT add any markdown syntax, language identifiers, or code fences",
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
  role "Extract contact information and meeting details from EmailFilterResult.",
  instruction "You have access to understand and parse the data extracted from EmailFilterResult scratchpad.

STEP 1: Extract emails and names from the EmailFilterResult scratchpad:
- From {{EmailFilterResult.emailSender}}: extract email address and name (if 'Name <email>' format, extract both.)
- From {{EmailFilterResult.emailRecipients}}: same extraction logic

STEP 2: Determine which participant is the CONTACT (not the user) - USE ONLY THE ACTUAL DATA PROVIDED:
- The gmail owner email is {{EmailFilterResult.gmailOwnerEmail}} - this person is the USER, NOT the contact
- CRITICAL: The contactEmail you return MUST NEVER equal {{EmailFilterResult.gmailOwnerEmail}}
- LOGIC: Compare the actual emails to identify the external contact:
  * Read the actual value of {{EmailFilterResult.emailSender}}
  * Read the actual value of {{EmailFilterResult.emailRecipients}}
  * Read the actual value of {{EmailFilterResult.gmailOwnerEmail}}
  * If emailSender = gmailOwnerEmail, then the contact is the person in emailRecipients
  * If emailRecipients = gmailOwnerEmail, then the contact is the person in emailSender
  * Extract the contact's email, firstName, and lastName from the person who is NOT the gmail owner
- FINAL VERIFICATION: Confirm contactEmail ≠ {{EmailFilterResult.gmailOwnerEmail}} before returning

STEP 3: Extract meeting details from the EmailFilterResult values:
- meetingTitle: exact value from {{EmailFilterResult.emailSubject}} field
- meetingDate: exact value from {{EmailFilterResult.emailDate}} field (keep ISO 8601 format)
- meetingBody: summarize the {{EmailFilterResult.emailBody}} in a descriptive clear structure. If there are action items mentioned, create numbered action items.

STEP 4: Return ContactInfo with ACTUAL extracted values from the scratchpad data:
- contactEmail: the ACTUAL email you extracted (not an example)
- contactFirstName: the ACTUAL first name you extracted (not an example)
- contactLastName: the ACTUAL last name you extracted (not an example, can be empty string if not found)
- meetingTitle: the ACTUAL {{EmailFilterResult.emailSubject}} value (not an example)
- meetingBody: the ACTUAL summarized {{EmailFilterResult.emailBody}} (not an example)
- meetingDate: the ACTUAL {{EmailFilterResult.emailDate}} value (not an example)

CRITICAL RULES - READ CAREFULLY:
- DO NOT use placeholder values like \"sam@something.com\" or \"Project Discussion\"
- DO NOT use example data - ONLY use the ACTUAL data from EmailFilterResult scratchpad
- DO NOT return empty strings - extract actual values from the provided data
- DO NOT create fictional data
- Extract contactFirstName and contactLastName from the name part of \"Name <email>\" format
- If names not in email format, try to find them in the email body (e.g., after \"Hi,\" or in signature)

CRITICAL OUTPUT FORMAT RULES:
- NEVER wrap your response in markdown code blocks (``` or ``)
- NEVER use markdown formatting in your response
- NEVER add JSON formatting with backticks
- Do NOT add any markdown syntax, language identifiers, or code fences",
  responseSchema agenticcrm.core/ContactInfo,
  retry classifyRetry
}

@public agent findExistingContact {
  llm "gpt_llm",
  role "Search for an existing contact in HubSpot by email address.",
  instruction "You MUST invoke the agenticcrm.core/FindContactByEmail tool to search for a contact.

STEP 1: Call agenticcrm.core/FindContactByEmail tool with:
- email: {{ContactInfo.contactEmail}}

STEP 2: Wait for the tool response. It will return a ContactSearchResult with:
- contactFound: true or false
- existingContactId: the contact ID if found

STEP 3: Return the tool's exact response.

CRITICAL RULES:
- You MUST call the FindContactByEmail tool - do NOT skip this step
- Use the ACTUAL response from the tool
- DO NOT make up whether a contact exists
- DO NOT fabricate contact IDs

CRITICAL OUTPUT FORMAT RULES:
- NEVER wrap your response in markdown code blocks (``` or ``)
- NEVER use markdown formatting in your response
- NEVER add JSON formatting with backticks
- Output ONLY the raw JSON object directly
- Do NOT add any markdown syntax, language identifiers, or code fences",
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

@public agent createNewContact {
    llm "sonnet_llm",
    role "Invoke agenticcrm.core/createHubspotContact to create a HubSpot contact",
    instruction "Invoke the agenticcrm.core/createHubspotContact tool with these exact field names:
- email: {{ContactInfo.contactEmail}}
- firstName: {{ContactInfo.contactFirstName}}
- lastName: {{ContactInfo.contactLastName}}

If firstName or lastName are empty strings, still provide them as empty strings \"\".

After the tool returns, extract the 'id' value from the response and return it as finalContactId.

CRITICAL:
- Use the ACTUAL id from the tool response (numeric string like \"401\" or \"8801\")
- DO NOT return UUID format (8-4-4-4-12)
- DO NOT return \"uuid()\"
- DO NOT make up an ID

CRITICAL OUTPUT FORMAT RULES:
- NEVER wrap your response in markdown code blocks (``` or ``)
- NEVER use markdown formatting
- NEVER add JSON formatting with backticks
- Output ONLY the raw JSON object directly",
    responseSchema agenticcrm.core/ContactResult,
    retry classifyRetry,
    tools [agenticcrm.core/createHubspotContact]
}

@public agent updateExistingContact {
    llm "gpt_llm",
    role "Add existing contact into agenticcrm.core/ContactResult",
    instruction "Extract {{ContactSearchResult.existingContactId}} and return it as finalContactId.

CRITICAL: 
- Use the exact ID value from ContactSearchResult.existingContactId
- This is a numeric string like \"401\" or \"12345\"
- DO NOT return \"uuid()\" or empty values

CRITICAL OUTPUT FORMAT RULES:
- NEVER wrap your response in markdown code blocks (``` or ``)
- NEVER use markdown formatting in your response
- NEVER add JSON formatting with backticks
- Output ONLY the raw JSON object directly
- Do NOT add any markdown syntax, language identifiers, or code fences",
    responseSchema agenticcrm.core/ContactResult,
    retry classifyRetry
}

workflow skipProcessing {
  {SkipResult {
    skipped true,
    reason "Email filtered out (automated sender or newsletter)"
  }}
}

@public agent createMeeting {
  llm "sonnet_llm",
  role "Create a meeting record in HubSpot to log the email interaction.",
  instruction "STEP 1: Convert {{ContactInfo.meetingDate}} from ISO 8601 to Unix milliseconds.
Calculate end time as start + 3600000 (1 hour).

STEP 2: Create meeting using hubspot/Meeting with these EXACT fields:
- meeting_title: use {{ContactInfo.meetingTitle}}
- meeting_body: use {{ContactInfo.meetingBody}}
- timestamp: Unix milliseconds as string
- meeting_outcome: use the string 'COMPLETED'
- meeting_start_time: Unix milliseconds as string
- meeting_end_time: start + 3600000 as string (must be a string)
- owner: use {{EmailFilterResult.hubspotOwnerId}} as string
- associated_contacts: use {{ContactResult.finalContactId}} as string (this associates the meeting with the contact)

CRITICAL REQUIREMENTS:
- All timestamp fields (timestamp, meeting_start_time, meeting_end_time) MUST be Unix milliseconds as strings
- The owner field must be the HubSpot owner ID as a string
- The associated_contacts field must contain the contact ID from ContactResult.finalContactId
- Do NOT skip the associated_contacts field - it's required to link the meeting to the contact in HubSpot

CRITICAL OUTPUT FORMAT RULES:
- NEVER wrap your response in markdown code blocks (``` or ``)
- NEVER use markdown formatting in your response
- NEVER add JSON formatting with backticks
- Do NOT add any markdown syntax, language identifiers, or code fences",
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
  llm "gpt_llm",
  role "You coordinate the complete CRM workflow: filter the email, extract contact and meeting information, find or create the contact in HubSpot, and create the meeting with proper associations."
}

workflow @after create:gmail/Email {
    {CRMConfig? {}} @as [crmConfig];
    "Email sender is: " + gmail/Email.sender + " Email recipients are: " + gmail/Email.recipients + " Email date is: " + gmail/Email.date + " Email subject is: " + gmail/Email.subject + " Email body is: " + gmail/Email.body + " Email thread_id is: " + gmail/Email.thread_id + " Gmail main owner email is: " + crmConfig.gmailEmail + " Hubspot Owner id is: " + crmConfig.ownerId  @as completeMessage;

    console.log(completeMessage);
    {crmManager {message completeMessage}}
}
