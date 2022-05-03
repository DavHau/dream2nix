{
  fetchgit,
  lib,
  utils,
  ...
}: let
  b = builtins;

  # check if a string is a git ref
  isGitRef = b.match "refs/(heads|tags)/.*";
  # check if a string is a git rev
  isGitRev = b.match "[a-f0-9]*";
in {
  inputs = [
    "url"
    "rev"
  ];

  versionField = "rev";

  outputs = {
    url,
    rev,
    ...
  } @ inp:
    if isGitRef rev == null && isGitRev rev == null
    then throw ''rev must either be a sha1 revision or "refs/heads/branch-name" or "refs/tags/tag-name"''
    else if isGitRef (inp.ref or "") == null
    then throw ''ref must be in either "refs/heads/branch-name" or "refs/tags/tag-name" format''
    else let
      b = builtins;

      refAndRev =
        # if the source specifies a ref, then we add both the ref and rev
        if inp ? ref
        then {inherit (inp) rev ref;}
        # otherwise check if the rev is a ref, if it is add to ref
        else if b.match "refs/(heads|tags)/.*" inp.rev != null
        then {ref = inp.rev;}
        # if the rev isn't a ref, then it is a rev, so add it there
        else {rev = inp.rev;};
    in {
      calcHash = algo:
        utils.hashPath algo
        (b.fetchGit
          (refAndRev
            // {
              inherit url;
              # disable fetching all refs if the source specifies a ref
              allRefs = inp.ref or null == null;
              submodules = true;
            }));

      # git can either be verified via revision or hash.
      # In case revision is used for verification, `hash` will be null.
      fetched = hash:
        if hash == null
        then
          if ! refAndRev ? rev
          then throw "Cannot fetch git repo without integrity. Specify at least 'rev' or 'sha256'"
          else
            b.fetchGit
            (refAndRev
              // {
                inherit url;
                allRefs = true;
                submodules = true;
              })
        else
          fetchgit
          (refAndRev
            // {
              inherit url;
              fetchSubmodules = true;
              sha256 = hash;
            });
    };
}
