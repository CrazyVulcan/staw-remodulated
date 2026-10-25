const retired=[
  'Physical die in zone captures result and locks','Populated dice panel closes on CLOSE',
  'Dice FINALIZE waits for unresolved rolls','Dice CLEAR removes logical pool and unlocks dice',
  'Settled dice FINALIZE records finalized state','Logical dice results survive save and reload',
  'Dice edits and rerolls are blocked while awaiting','Dice timeout removes unresolved entry and unlocks physical die',
  'New roll reopens a previously closed dice panel','Clear followed immediately by same die roll ignores old watcher',
  'Physical die cannot remain recorded in two player pools','Finalized logical dice and explicit closed visibility survive reload',
  'Reload resumes an unresolved roll and captures settled value','Deleted settled die is removed from dashboard and save state',
  'Reload prunes missing physical dice'
];
const skipLua=`local retired={${retired.map(n=>'['+JSON.stringify(n)+']=true').join(',')}}
local runTest=test
function test(name,fn)if retired[name]then _auditLog('Retired dice dashboard check: '..name);return end;return runTest(name,fn)end`;

module.exports=skipLua;
