-- Built-in builds, by class. Each step is { "Talent Name", rankToReach }, in the order to learn them.
-- A talent can appear more than once (e.g. 1 point early, the rest later).
-- Names must match the talent names in WoW Forever's talent window.
TalentGuideBuiltins = {
  HUNTER = {
    {
      name = "Beast Mastery (leveling)",
      notes = "Pet damage and survivability first, run speed for questing, then Bestial Wrath. Leftover points go to Marksmanship crit and mana.",
      steps = {
        { "Deadly Aspects", 5 },
        { "Focused Fire", 2 },
        { "Pathfinding", 2 },
        { "Endurance Training", 1 },
        { "Unleashed Fury", 5 },
        { "Ferocity", 5 },
        { "Intimidation", 1 },
        { "Spirit Bond", 2 },
        { "Bestial Discipline", 2 },
        { "Frenzy", 5 },
        { "Bestial Wrath", 1 },
        { "Endurance Training", 5 },
        { "Improved Mend Pet", 2 },
        { "Bestial Swiftness", 1 },
        { "Improved Revive Pet", 2 },
        { "Lethal Attacks", 5 },
        { "Efficiency", 5 },
        { "Hawk Eye", 1 },
      },
    },
  },
}
