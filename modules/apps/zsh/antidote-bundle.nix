specs:
let
  allowedAttrs = [
    "kind"
    "path"
    "repo"
  ];
  validRepo =
    repo:
    let
      components = builtins.filter builtins.isString (builtins.split "/" repo);
      owner = builtins.elemAt components 0;
      name = builtins.elemAt components 1;
    in
    builtins.isString repo
    && builtins.match "[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?/[A-Za-z0-9._-]+" repo != null
    && builtins.length components == 2
    && builtins.stringLength owner <= 39
    && builtins.match ".*--.*" owner == null
    && builtins.stringLength name <= 100
    && name != "."
    && name != "..";
  validPath =
    path:
    let
      components = builtins.filter builtins.isString (builtins.split "/" path);
    in
    builtins.isString path
    && path != ""
    && builtins.match "[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*" path != null
    && builtins.all (component: component != "." && component != "..") components;
  render =
    spec:
    if !builtins.isAttrs spec then
      throw "antidote bundle spec must be an attribute set"
    else
      let
        unknownAttrs = builtins.filter (name: !(builtins.elem name allowedAttrs)) (builtins.attrNames spec);
        repo = spec.repo or null;
        kind = spec.kind or null;
        path = spec.path or null;
      in
      if unknownAttrs != [ ] then
        throw "antidote bundle spec has unknown attributes: ${builtins.concatStringsSep ", " unknownAttrs}"
      else if !validRepo repo then
        throw "antidote bundle spec repo must be a GitHub owner/repo"
      else if spec ? kind && kind != "defer" then
        throw "antidote bundle spec kind must be defer"
      else if spec ? path && !validPath path then
        throw "antidote bundle spec path must contain safe relative components"
      else
        builtins.concatStringsSep " " (
          [ repo ]
          ++ (if spec ? kind then [ "kind:${kind}" ] else [ ])
          ++ (if spec ? path then [ "path:${path}" ] else [ ])
        );
  rendered = map render specs;
  requireUnique =
    lines:
    if lines == [ ] then
      lines
    else if builtins.elem (builtins.head lines) (builtins.tail lines) then
      throw "antidote bundle specs must not contain duplicates"
    else
      [ (builtins.head lines) ] ++ requireUnique (builtins.tail lines);
in
if !builtins.isList specs then
  throw "antidote bundle specs must be a list"
else
  requireUnique rendered
