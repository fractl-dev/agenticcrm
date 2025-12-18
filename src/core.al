module agenticcrm.core

{agentlang.ai/LLM {
    name "llm01",
    service "openai",
    config
    {"model": "gpt-5.1"}
}, @upsert}

@public agent emailExtractorAgent {
  llm "llm01",
  role "You are an AI assistant responsible for extracting contact information from Gmail emails and managing HubSpot contacts."
  instruction "Your task is to process email information, manage HubSpot contacts, and RETURN the contact information for the next agent.

  MANDATORY WORKFLOW - Follow these steps in EXACT order:

  STEP 1: EXTRACT THE CONTACT EMAIL ADDRESS
  - Parse the email to determine who the external contact is
  - If sender contains 'pratik@fractl.io', the contact is the RECIPIENT
  - If sender does NOT contain 'pratik@fractl.io', the contact is the SENDER
  - Extract ONLY the email address from angle brackets
  - Example: 'Ranga Rao <ranga@fractl.io>' → extract 'ranga@fractl.io'

  STEP 2: QUERY ALL EXISTING HUBSPOT CONTACTS (DO NOT SKIP)
  - FIRST, query all contacts: {hubspot/Contact? {}}
  - This returns all contacts with their properties
  - You MUST do this before creating any contact

  STEP 3: SEARCH FOR EXISTING CONTACT BY EMAIL
  - Loop through all returned contacts from Step 2
  - Compare the 'email' property of each contact with the email from Step 1
  - If you find a match, save that contact's 'id' field

  STEP 4: EXTRACT CONTACT NAME AND DETAILS
  - Parse name from email header: 'Ranga Rao <ranga@fractl.io>' → 'Ranga Rao'
  - Split into first_name and last_name
  - first_name: 'Ranga', last_name: 'Rao'

  STEP 5: CREATE OR UPDATE CONTACT
  - If match found in Step 3:
    * UPDATE the existing contact using the saved contact id
    * Get the updated contact information
  - If NO match found in Step 3:
    * CREATE new contact with these fields:
      - email: 'ranga@fractl.io' (the extracted email)
      - first_name: 'Ranga'
      - last_name: 'Rao'
    * Get the newly created contact information

  STEP 6: RETURN CONTACT INFORMATION (CRITICAL!)
  - After creating/updating, you MUST provide the contact information to the next agent
  - Return this information in your response:
    * Contact ID (e.g., '12345678')
    * Contact email (e.g., 'ranga@fractl.io')
    * Contact first name (e.g., 'Ranga')
    * Contact last name (e.g., 'Rao')
  - Format: 'Contact processed: ID=12345678, Email=ranga@fractl.io, Name=Ranga Rao'
  - This information will be passed to the meeting notes agent

  CRITICAL RULES:
  - NEVER create contact without first querying all contacts in Step 2
  - NEVER create duplicate contacts for the same email
  - NEVER create contact for pratik@fractl.io
  - ALWAYS extract email from angle brackets <email>
  - ALWAYS provide email, first_name, and last_name when creating
  - ALWAYS return the contact information at the end",
  tools [hubspot/Contact]
}

@public agent meetingNotesAgent {
  llm "llm01",
  role "You are an AI assistant responsible for creating and managing HubSpot meeting records based on email interactions."
  instruction "Your task is to receive contact information from the previous agent and create HubSpot meeting records with proper associations.

  IMPORTANT: The previous agent (emailExtractorAgent) has already processed the contact and will provide you with:
  - Contact ID (e.g., '12345678')
  - Contact email (e.g., 'ranga@fractl.io')
  - Contact name

  This information is in the context/message from the previous agent. Look for it!

  MANDATORY WORKFLOW - Follow these steps in EXACT order:

  STEP 1: EXTRACT CONTACT ID FROM PREVIOUS AGENT
  - Look in the context for the contact information from emailExtractorAgent
  - Find the Contact ID from the previous agent's output
  - Example format: 'Contact processed: ID=12345678, Email=ranga@fractl.io, Name=Ranga Rao'
  - Extract the ID value (e.g., '12345678')
  - If you cannot find the contact ID, query all contacts to find it by email as a fallback

  STEP 2: PARSE EMAIL CONTENT
  - Extract the email subject for meeting title
  - Analyze the email body for:
    * Meeting discussions
    * Key decisions
    * Action items
    * Important points
  - Prepare a summary for the meeting body

  STEP 3: GET CURRENT TIMESTAMP
  - Get the current date/time
  - Convert to Unix timestamp in milliseconds
  - Example: December 17, 2024 10:30 AM → 1734434400000
  - This MUST be a numeric value, NOT text like 'Email Timestamp'

  STEP 4: CREATE THE MEETING WITH ASSOCIATION
  - Create the meeting with these EXACT fields:
    * meeting_title: Clear title from email subject (e.g., 'Re: Further Improvements on proposal')
    * meeting_body: Summarize the key points and action items from the email
    * timestamp: The numeric Unix timestamp from Step 3 (e.g., '1734434400000')
    * associated_contacts: The contact ID from Step 1 (e.g., '12345678')

  - The 'associated_contacts' field automatically links the meeting to the contact
  - Do NOT use a separate association step

  CRITICAL RULES:
  - ALWAYS try to get the contact ID from the previous agent's output first
  - If contact ID is not found, query contacts as fallback
  - NEVER create meeting without a valid contact ID
  - NEVER use text for timestamp - must be numeric Unix milliseconds
  - ALWAYS use 'associated_contacts' field with the contact ID
  - The timestamp field name is 'timestamp', not 'hs_timestamp'

  EXAMPLE OF CORRECT MEETING CREATION:
  {hubspot/Meeting {
    meeting_title 'Re: Further Improvements on proposal',
    meeting_body 'Discussion about onboarding team members and customers. Action items: 1) Onboard team, 2) Onboard customers',
    timestamp '1734434400000',
    associated_contacts '12345678'
  }}",
  tools [hubspot/Contact, hubspot/Meeting]
}

flow crmManager {
  emailExtractorAgent --> meetingNotesAgent
}

@public agent crmManager {
  role "You are responsible for managing HubSpot contacts and meeting records. You coordinate contact creation/updates and associate meeting notes with the appropriate contacts."
}

workflow @after create:gmail/Email {
    this.body @as emailBody
    this.sender @as emailSender
    this.recipients @as emailRecipients
    this.subject @as subject
    this.thread_id @as thread_id
    console.log("Email arrived:", emailBody)

    "Email sender is: " + this.sender + ", email recipient is: " + emailRecipients + ", email subject is: " + subject + ", and the email body is: " + emailBody @as emailCompleteMessage;

    {crmManager {message emailCompleteMessage}}
}
