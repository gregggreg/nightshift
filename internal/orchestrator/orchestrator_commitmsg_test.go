package orchestrator

import (
	"strings"
	"testing"

	"github.com/marcus/nightshift/internal/commitmsg"
	"github.com/marcus/nightshift/internal/tasks"
)

func commitMsgTestTask() *tasks.Task {
	return &tasks.Task{
		ID:          "commit-normalize",
		Title:       "Commit Message Normalizer",
		Description: "Standardize commit message format",
		Type:        tasks.TaskType("commit-normalize"),
	}
}

// The prompts must keep instructing agents with the exact trailers the
// orchestrator has always required, now sourced from internal/commitmsg.
func TestPrompts_ContainNightshiftTrailers(t *testing.T) {
	o := New()
	task := commitMsgTestTask()
	plan := &PlanOutput{Steps: []string{"step1"}, Description: "test plan"}

	prompts := map[string]string{
		"plan":      o.buildPlanPrompt(task),
		"implement": o.buildImplementPrompt(task, plan, 1),
	}
	for name, prompt := range prompts {
		if !strings.Contains(prompt, "Nightshift-Task: commit-normalize") {
			t.Errorf("%s prompt missing task trailer\nGot:\n%s", name, prompt)
		}
		if !strings.Contains(prompt, "Nightshift-Ref: https://github.com/marcus/nightshift") {
			t.Errorf("%s prompt missing ref trailer\nGot:\n%s", name, prompt)
		}
	}
}

// Both prompts must embed the same canonical spec the validator enforces, so
// agents are never told a format the commit-msg hook would reject.
func TestPrompts_EmbedCanonicalSpec(t *testing.T) {
	o := New()
	task := commitMsgTestTask()
	plan := &PlanOutput{Steps: []string{"step1"}, Description: "test plan"}

	spec := commitmsg.PromptSpec("commit-normalize")
	for name, prompt := range map[string]string{
		"plan":      o.buildPlanPrompt(task),
		"implement": o.buildImplementPrompt(task, plan, 1),
	} {
		if !strings.Contains(prompt, spec) {
			t.Errorf("%s prompt does not embed commitmsg.PromptSpec\nGot:\n%s", name, prompt)
		}
		if !strings.Contains(prompt, "type(scope)") {
			t.Errorf("%s prompt missing the header format\nGot:\n%s", name, prompt)
		}
	}
}

// The spec handed to agents must itself describe a message the validator
// accepts: the example in the spec is checked against the real rules.
func TestPromptSpecExampleValidates(t *testing.T) {
	example := "feat(cli): add commit message normalizer\n\n" +
		"Adds a nightshift commit-msg subcommand that checks and rewrites commit\n" +
		"messages so every commit in the repository shares one format.\n\n" +
		"Nightshift-Task: commit-normalize\n" +
		"Nightshift-Ref: https://github.com/marcus/nightshift\n"

	if !strings.Contains(commitmsg.Spec(), strings.TrimRight(example, "\n")[:40]) {
		t.Fatalf("spec example drifted; update this test alongside commitmsg.Spec()")
	}
	m, err := commitmsg.Parse(example)
	if err != nil {
		t.Fatalf("parsing the spec example: %v", err)
	}
	if issues := commitmsg.Validate(m); commitmsg.HasErrors(issues) {
		t.Errorf("the spec's own example fails validation: %v", issues)
	}
}
