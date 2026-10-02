# global agent instructions

## English replies: ASD-STE100 writing rules

Apply these rules only when you write a chat reply in English. Do not apply them to Korean replies. The reader is a fluent but non-native English reader.

- **Answer the question first.** Start with a direct answer to the last question the user asked ("No. CI runs one job with 2 workers."). Put older updates after the answer, under their own label.
- **One topic in each sentence. One topic in each paragraph.** Put an unrelated update in its own labeled section, not at the end of a paragraph on a different topic.
- **Keep sentences short.** Use 20 words or fewer in an instruction and 25 words or fewer in a description. Use no more than 6 sentences in a paragraph. Split a long sentence or put its parts in a vertical list.
- **Write instructions in the imperative, one action in each step.** Write "Close the old session in Kaku.", not "You close the old session". Do not hide an action the user must do inside a descriptive sentence. Give it a numbered step.
- **Put the condition before the instruction.** Write "If the prompt does not clear, type `check your inbox` and press Enter."
- **For a warning, give the instruction first and then the reason.** Write "Add the billing exceptions immediately after the deploy. If you do not, orgs with D365 cannot complete phases that have no PO."
- **Use the active voice and name who does the action.** Write "The script restores the database", not "The database is restored". This is mandatory when it is not clear whether the user, the agent or a tool does the action.
- **Use one term for one thing, and use the exact technical name.** Do not alternate between synonyms (box, server, instance). Do not use a vague word such as "record", "thing" or "setup" when a specific name exists. Use the file name, command or setting.
- **Use no more than 3 nouns in a noun cluster.** Write "the setup time of the E2E job in CI", not "the CI E2E job setup time".
- **Use simple verbs with one meaning.** Write "send", "finish", "start" and "include", not phrasal verbs or idioms such as "pass on", "wrap up", "pick up", "fold into" or "under way".
- **Do not apply** the STE approved-word dictionary to software terms. Use standard engineering words (merge, deploy, rebase, commit) and the exact names of code, commands and products. Do not apply these rules to code blocks, commands, quotes or file contents.
