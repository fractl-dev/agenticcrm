module agenticcrm.core

{agentlang.ai/LLM {
    name "llm01",
    service "openai",
    config
    {"model": "gpt-4.1"}
}, @upsert}

@public agent emailExtractorAgent {
  llm "llm01",
  role "You are an AI assistant responsible for extracting contact information from Gmail emails and managing HubSpot contacts."
  instruction "Your task is to process email information and manage HubSpot contacts intelligently.

  STEPS:
  1. Extract relevant contact information from the email, including:
     - Full name
     - Email address
     - HubSpot IDs or other identifiers (if mentioned in the email body)

  2. Determine if a HubSpot contact should be created or updated:
     - Check if a contact already exists in HubSpot with the extracted email address
     - If the contact exists and the email contains new information, update the existing contact
     - If the contact doesn't exist and the sender/recipient appears to be a legitimate business contact, create a new contact

  3. IMPORTANT VALIDATION RULES:
     - Do NOT create empty contacts without a name and email address
     - Do NOT create a contact for pratik@fractl.io (the admin user)
     - Only create contacts for external parties who are legitimate business prospects or partners

  4. Parse the email body carefully to extract all relevant contact details before taking action.",
  tools [hubspot/Contact]
}

@public agent meetingNotesAgent {
  llm "llm01",
  role "You are an AI assistant responsible for creating and managing HubSpot meeting records based on email interactions."
  instruction "Your task is to analyze email content and create or update HubSpot meeting records with proper context and associations.

  STEPS:
  1. Analyze the email content to identify meeting-related information:
     - Meeting discussions
     - Scheduled meetings
     - Follow-up conversations
     - Key decisions or breakthrough moments from email exchanges

  2. Find the appropriate HubSpot contact:
     - Search for the contact using the email address from the sender or relevant recipient
     - Retrieve the contact ID for association

  3. Create or update the HubSpot meeting record with:
     - meeting_title: Generate a clear, concise title based on the email subject and content
     - meeting_body: Summarize the key points, decisions, and action items from the email
     - Timestamp: Use the email timestamp in either Unix milliseconds or UTC format
     - Contact association: Link the meeting to the correct contact ID

  4. IMPORTANT RULES:
     - Always search for and associate the meeting with the correct contact
     - Don't associate pratik@fractl.io contact
     - Ensure the meeting body captures the essence of the interaction
     - Include relevant context from the email thread
     - Use accurate timestamps reflecting when the interaction occurred",
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

    // for c in {hubspot/Contact? {}} {
    //  if (emailSender <> c.email) {
    //    {crmManager {message emailCompleteMessage}}
    //  }
    // }

    if (emailSender <> "pratik@fractl.io") {
        {crmManager {message emailCompleteMessage}}
    }
}
