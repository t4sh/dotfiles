# UX, research, and handoff routing contract

Load this reference for information architecture, task flows, interaction contracts, user research, research synthesis, uncertainty prototypes, or design handoff.

## Select the UX mode

Choose one mode before selecting a skill. The mode defines the artifact; a skill supplies its method.

| Design request | Primary owner | Required artifact |
| --- | --- | --- |
| Information architecture, navigation, task flow, state model, or interaction contract | Core UX Architect posture | Flow or IA map plus state matrix, interaction rules, and explicit assumptions |
| Plan or conduct user research | `user-research` | Research question, participant/method plan, evidence, and limitations |
| Synthesize supplied research | `research-synthesis` | Themes, evidence-linked insights, tensions, and prioritized implications |
| Explore one uncertain UI or state-model question with disposable code | `prototype` | Runnable prototype, the question it tests, and a recorded verdict |
| Prepare a finished design for engineering | `design-handoff` | Implementable component, token, behavior, state, asset, and acceptance specification |

`prototype` owns disposable evidence for one uncertain question and is selected only from this reference; production interface implementation belongs to the interface design route. Handoff specifies a finished design and does not silently become implementation.

## UX operating sequence

1. **Inspect.** Read the supplied evidence, existing product model, design authorities, and relevant rendered behavior. Done when the current user, task, constraints, and evidence gaps can be named.
2. **Frame.** Select the mode, question, required artifact, and decision it must support. Separate evidence from assumptions. Done when the artifact has a concrete evaluation criterion.
3. **Structure.** Resolve flows, information relationships, state behavior, findings, or implementation contracts at the fidelity the mode requires. Done when every material branch or claim is accounted for.
4. **Verify.** Trace the artifact to source evidence and its required contract. Record limitations and the cheapest validation that would change an uncertain decision. Done when evidence is linked or unavailable checks have an executable handoff.

If a request continues into visual direction or rendered implementation, finish this artifact first and then load the interface design route. Repository inspection supports the work; it is not a design phase.
