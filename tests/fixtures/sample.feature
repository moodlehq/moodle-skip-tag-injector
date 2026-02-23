Feature: Sample feature for testing skip tag injection

  @existing_tag
  Scenario: Scenario with an existing tag
    Given I have a simple scenario
    Then it should work

  Scenario: Simple scenario without tags
    Given I have a simple scenario
    Then it should work

  Scenario: Scenario with special chars (javascript enabled)
    Given I have a scenario with parentheses
    Then it should match correctly

  @existing_tag @another_tag
  Scenario: Scenario already tagged with skip
    Given I have a scenario already tagged
    Then it should not get a second skip

  @existing_tag @skip @another_tag
  Scenario: Scenario already skipped in the middle of tags
    Given I have a scenario already skipped
    Then it should not be duplicated
  Scenario Outline: Scenario outline without tags
    Given I have a scenario outline with <value>
    Then it should work
    Examples:
      | value |
      | foo   |
      | bar   |
