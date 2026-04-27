use "collections"
use "files"

class ref AllWalkHandler is WalkHandler
  let files: Array[String] ref = Array[String]

  new create() =>
    None

  fun ref apply(dir_path: FilePath, dir_entries: Array[String] ref) =>
    for entry in dir_entries.values() do
      try
        let child = dir_path.join(entry)?
        let info = FileInfo(child)?
        if info.file then files.push(Path.rel(Path.cwd(), child.path)?) end
      end
    end

primitive NativeImport
  fun import_command(env: Env, source: String, commit: String) =>
    let failures = Array[String]
    let prep: String val = recover val
      "rm -rf third_party/boon-upstream examples/upstream && " +
      "mkdir -p third_party examples fixtures examples/upstream_overrides && " +
      "git clone --filter=blob:none " + _shell_quote(source) + " third_party/boon-upstream && " +
      "git -C third_party/boon-upstream checkout " + _shell_quote(commit) + " && " +
      "test -d third_party/boon-upstream/playground/frontend/src/examples && " +
      "cp -a third_party/boon-upstream/playground/frontend/src/examples examples/upstream"
    end
    let prep_status = _system_status(prep)
    if prep_status != 0 then failures.push("failed to clone, checkout, or copy upstream examples") end
    if failures.size() == 0 then
      _migrate_sources(env, failures)
      let copy_status = _system_status("if [ -d examples/upstream_overrides ]; then cp -a examples/upstream_overrides/. examples/upstream/; fi")
      if copy_status != 0 then failures.push("failed to apply upstream overrides") end
    end
    if failures.size() == 0 then
      _write_file(env, "fixtures/upstream_pin.json", _pin_json(env, source, commit))
      _write_file(env, "fixtures/corpus_manifest.json", _manifest_json(env, source, commit))
      let inventory = _syntax_inventory(env)
      _write_file(env, "fixtures/syntax_inventory.json", _inventory_json(inventory))
      _write_file(env, "fixtures/feature_matrix.md", _feature_matrix(env, inventory))
    end
    if failures.size() == 0 then
      env.out.print("imported " + _example_count(env).string() + " upstream example groups")
      env.out.print("shared root files: " + _shared_root_files(env).size().string())
      env.out.print("tree hash: " + _tree_hash(env))
      env.exitcode(0)
    else
      for failure in failures.values() do env.err.print("error: " + failure) end
      env.exitcode(1)
    end

  fun _migrate_sources(env: Env, failures: Array[String] ref) =>
    for file in _walk_files(env, "examples/upstream").values() do
      if file.at(".bn", -3) then
        try
          let text = _read_file(env, file)?
          let migrated = _replace_all(_replace_all(text, "|> LINK", "|> SOURCE"), "LINK", "SOURCE")
          if migrated != text then _write_file(env, file, migrated) end
        else
          failures.push("failed to migrate " + file)
        end
      end
    end

  fun _pin_json(env: Env, source: String, commit: String): String =>
    let out = String
    out.append("{\n")
    out.append("  \"repo\": \""); _append_json(out, source); out.append("\",\n")
    out.append("  \"commit\": \""); _append_json(out, commit); out.append("\",\n")
    out.append("  \"source_root\": \"playground/frontend/src/examples\",\n")
    out.append("  \"imported_root\": \"examples/upstream\",\n")
    out.append("  \"override_root\": \"examples/upstream_overrides\",\n")
    out.append("  \"tree_hash\": \""); out.append(_tree_hash(env)); out.append("\",\n")
    out.append("  \"tree_hash_command\": \"build/bin/boonpony import-upstream native tree checksum over examples/upstream and examples/upstream_overrides\"\n")
    out.append("}\n")
    out.clone()

  fun _manifest_json(env: Env, source: String, commit: String): String =>
    let out = String
    out.append("{\n")
    out.append("  \"generated_by\": \"build/bin/boonpony import-upstream\",\n")
    out.append("  \"source_repo\": {\n")
    out.append("    \"url\": \""); _append_json(out, source); out.append("\",\n")
    out.append("    \"commit\": \""); _append_json(out, commit); out.append("\",\n")
    out.append("    \"example_root\": \"playground/frontend/src/examples\",\n")
    out.append("    \"imported_root\": \"examples/upstream\",\n")
    out.append("    \"override_root\": \"examples/upstream_overrides\"\n")
    out.append("  },\n")
    out.append("  \"shared_root_files\": [")
    let shared = _shared_root_files(env)
    var shared_index: USize = 0
    for item in shared.values() do
      if shared_index > 0 then out.append(",") end
      out.append("\n    {\"path\": \""); _append_json(out, item._1); out.append("\", \"kind\": \""); _append_json(out, item._2); out.append("\"}")
      shared_index = shared_index + 1
    end
    if shared.size() > 0 then out.append("\n  ") end
    out.append("],\n")
    out.append("  \"examples\": [\n")
    let examples = _examples(env)
    var index: USize = 0
    for ex in examples.values() do
      if index > 0 then out.append(",\n") end
      _append_example(out, ex)
      index = index + 1
    end
    out.append("\n  ]\n}\n")
    out.clone()

  fun _append_example(out: String ref, ex: (String, String, String, String, String, Array[String] val, Array[String] val)) =>
    (let name, let category, let source_path, let imported_path, let entry_file, let bn_files, let expected_files) = ex
    out.append("    {\n")
    out.append("      \"name\": \""); _append_json(out, name); out.append("\",\n")
    out.append("      \"category\": \""); _append_json(out, category); out.append("\",\n")
    out.append("      \"source_path\": \""); _append_json(out, source_path); out.append("\",\n")
    out.append("      \"imported_path\": \""); _append_json(out, imported_path); out.append("\",\n")
    out.append("      \"entry_file\": "); _append_nullable_string(out, entry_file); out.append(",\n")
    out.append("      \"bn_files\": "); out.append(_strings_json(bn_files)); out.append(",\n")
    out.append("      \"expected_file\": "); _append_nullable_string(out, try expected_files(0)? else "" end); out.append(",\n")
    out.append("      \"expected_files\": "); out.append(_strings_json(expected_files)); out.append(",\n")
    out.append("      \"parser_status\": \"NOT_RUN\",\n")
    out.append("      \"source_shape_status\": \"NOT_RUN\",\n")
    out.append("      \"runtime_status\": \"NOT_RUN\",\n")
    out.append("      \"terminal_status\": \"NOT_RUN\",\n")
    out.append("      \"browser_status\": \"NOT_RUN\",\n")
    out.append("      \"hard_gate\": false,\n")
    out.append("      \"blockers\": [],\n")
    out.append("      \"evidence\": []\n")
    out.append("    }")

  fun _examples(env: Env): Array[(String, String, String, String, String, Array[String] val, Array[String] val)] val =>
    let examples = recover trn Array[(String, String, String, String, String, Array[String] val, Array[String] val)] end
    for entry in _entries(env, "examples/upstream").values() do
      let full: String val = recover val "examples/upstream/" + entry end
      try
        let info = FileInfo(FilePath(FileAuth(env.root), full))?
        if info.directory then
          let files = _walk_files(env, full)
          let bn_files = _suffix(files, ".bn")
          let expected_files = _suffix(files, ".expected")
          examples.push((entry, "upstream", "playground/frontend/src/examples/" + entry, full, try bn_files(0)? else "" end, bn_files, expected_files))
        elseif info.file and entry.at(".bn", -3) then
          let base = _basename_without_suffix(entry, ".bn")
          let expected: String val = recover val "examples/upstream/" + base + ".expected" end
          let expected_files = if _file_exists(env, expected) then recover val [expected] end else recover val Array[String] end end
          examples.push((base + "_root", "upstream_root", "playground/frontend/src/examples/" + entry, full, full, recover val [full] end, expected_files))
        end
      end
    end
    consume examples

  fun _shared_root_files(env: Env): Array[(String, String)] val =>
    let shared = recover trn Array[(String, String)] end
    for entry in _entries(env, "examples/upstream").values() do
      let full: String val = recover val "examples/upstream/" + entry end
      try
        let info = FileInfo(FilePath(FileAuth(env.root), full))?
        if info.file and (not entry.at(".bn", -3)) and (not entry.at(".expected", -9)) then
          shared.push((full, _extension_kind(entry)))
        end
      end
    end
    consume shared

  fun _syntax_inventory(env: Env): Array[(String, USize, Array[String] val)] val =>
    let out = recover trn Array[(String, USize, Array[String] val)] end
    for token in _tokens().values() do
      var count: USize = 0
      let files = recover trn Array[String] end
      for file in _suffix(_walk_files(env, "examples/upstream"), ".bn").values() do
        try
          let hits = _count_word(_read_file(env, file)?, token)
          if hits > 0 then
            count = count + hits
            files.push(file)
          end
        end
      end
      out.push((token, count, consume files))
    end
    consume out

  fun _inventory_json(inventory: Array[(String, USize, Array[String] val)] val): String =>
    let out = String
    out.append("{\n")
    var index: USize = 0
    for item in inventory.values() do
      (let token, let count, let files) = item
      if index > 0 then out.append(",\n") end
      out.append("  \""); _append_json(out, token); out.append("\": {\"count\": "); out.append(count.string()); out.append(", \"files\": "); out.append(_strings_json(files)); out.append("}")
      index = index + 1
    end
    out.append("\n}\n")
    out.clone()

  fun _feature_matrix(env: Env, inventory: Array[(String, USize, Array[String] val)] val): String =>
    let out = String
    out.append("# Boon-Pony Feature Matrix\n\n")
    out.append("| Example | BN files | Expected | Parser | Source Shape | Runtime | Terminal |\n")
    out.append("|---|---:|---|---|---|---|---|\n")
    for ex in _examples(env).values() do
      out.append("| "); out.append(ex._1); out.append(" | "); out.append(ex._6.size().string()); out.append(" | "); out.append(if ex._7.size() > 0 then "yes" else "no" end); out.append(" | NOT_RUN | NOT_RUN | NOT_RUN | NOT_RUN |\n")
    end
    out.append("\n## Syntax Inventory\n\n")
    out.append("| Token | Count | Files |\n|---|---:|---:|\n")
    for item in inventory.values() do
      out.append("| "); out.append(item._1); out.append(" | "); out.append(item._2.string()); out.append(" | "); out.append(item._3.size().string()); out.append(" |\n")
    end
    out.clone()

  fun _tree_hash(env: Env): String =>
    var checksum: USize = 5381
    let files = Array[String]
    for file in _walk_files(env, "examples/upstream").values() do files.push(file) end
    for file in _walk_files(env, "examples/upstream_overrides").values() do files.push(file) end
    Sort[Array[String], String](files)
    for file in files.values() do
      checksum = _hash_text(checksum, file)
      try checksum = _hash_text(checksum, _read_file(env, file)?) end
    end
    "pony-" + checksum.string()

  fun _example_count(env: Env): USize => _examples(env).size()

  fun _tokens(): Array[String] val =>
    recover val ["SOURCE"; "LINK"; "LATEST"; "HOLD"; "THEN"; "WHEN"; "WHILE"; "BLOCK"; "SKIP"; "FLUSH"; "PASS"; "PASSED"; "LIST"; "MAP"; "FUNCTION"; "BITS"; "MEMORY"; "BYTES"; "TEXT"] end

  fun _count_word(text: String, token: String): USize =>
    var count: USize = 0
    var offset: ISize = 0
    while offset < text.size().isize() do
      try
        let found = text.find(token, offset)?
        let before_ok = (found == 0) or not _is_ident_byte(text.at_offset(found - 1)?)
        let after = found + token.size().isize()
        let after_ok = (after >= text.size().isize()) or not _is_ident_byte(text.at_offset(after)?)
        if before_ok and after_ok then count = count + 1 end
        offset = found + token.size().isize()
      else
        return count
      end
    end
    count

  fun _is_ident_byte(ch: U8): Bool =>
    ((ch >= 'A') and (ch <= 'Z')) or ((ch >= 'a') and (ch <= 'z')) or ((ch >= '0') and (ch <= '9')) or (ch == '_')

  fun _replace_all(text: String, needle: String, replacement: String): String =>
    let out = String
    var offset: ISize = 0
    while offset < text.size().isize() do
      try
        let found = text.find(needle, offset)?
        out.append(text.substring(offset, found))
        out.append(replacement)
        offset = found + needle.size().isize()
      else
        out.append(text.substring(offset))
        break
      end
    end
    out.clone()

  fun _walk_files(env: Env, root: String): Array[String] val =>
    let files = recover trn Array[String] end
    let path = FilePath(FileAuth(env.root), root)
    let handler = AllWalkHandler
    path.walk(handler)
    for file in handler.files.values() do files.push(file) end
    var i: USize = 0
    try
      while i < files.size() do
        var j = i + 1
        while j < files.size() do
          if files(j)? < files(i)? then
            let tmp = files(i)?
            files.update(i, files(j)?)?
            files.update(j, tmp)?
          end
          j = j + 1
        end
        i = i + 1
      end
    end
    consume files

  fun _entries(env: Env, root: String): Array[String] val =>
    let out = recover trn Array[String] end
    try
      let entries = Directory(FilePath(FileAuth(env.root), root))?.entries()?
      for entry in (consume entries).values() do out.push(entry) end
    end
    var i: USize = 0
    try
      while i < out.size() do
        var j = i + 1
        while j < out.size() do
          if out(j)? < out(i)? then
            let tmp = out(i)?
            out.update(i, out(j)?)?
            out.update(j, tmp)?
          end
          j = j + 1
        end
        i = i + 1
      end
    end
    consume out

  fun _suffix(files: Array[String] val, suffix: String): Array[String] val =>
    let out = recover trn Array[String] end
    for file in files.values() do if file.at(suffix, -suffix.size().isize()) then out.push(file) end end
    consume out

  fun _extension_kind(file: String): String =>
    try
      let parts = file.split_by(".")
      parts(parts.size() - 1)?
    else
      "file"
    end

  fun _basename_without_suffix(path': String, suffix: String): String =>
    if path'.at(suffix, -suffix.size().isize()) then path'.substring(0, (path'.size() - suffix.size()).isize()) else path' end

  fun _hash_text(start: USize, text: String): USize =>
    var checksum = start
    for ch in text.values() do checksum = ((checksum * 33) + ch.usize()) % 4294967291 end
    checksum

  fun _strings_json(items: Array[String] val): String =>
    let out = String
    out.append("[")
    var index: USize = 0
    for item in items.values() do
      if index > 0 then out.append(", ") end
      out.append("\""); _append_json(out, item); out.append("\"")
      index = index + 1
    end
    out.append("]")
    out.clone()

  fun _append_nullable_string(out: String ref, value: String) =>
    if value == "" then
      out.append("null")
    else
      out.append("\""); _append_json(out, value); out.append("\"")
    end

  fun _append_json(out: String ref, value: String) =>
    for ch in value.values() do
      match ch
      | '"' => out.append("\\\"")
      | '\\' => out.append("\\\\")
      | 10 => out.append("\\n")
      | 13 => out.append("\\r")
      | 9 => out.append("\\t")
      else
        if ch >= 32 then out.push(ch) end
      end
    end

  fun _read_file(env: Env, file: String): String ? =>
    let path = FilePath(FileAuth(env.root), file)
    let info = FileInfo(path)?
    with f = OpenFile(path) as File do
      f.read_string(info.size)
    end

  fun _write_file(env: Env, file: String, data: String) =>
    try
      (let dir, _) = Path.split(file)
      if dir != "" then FilePath(FileAuth(env.root), dir).mkdir() end
      with f = CreateFile(FilePath(FileAuth(env.root), file)) as File do
        f.set_length(0)
        f.write(data)
      end
    end

  fun _file_exists(env: Env, file: String): Bool =>
    FilePath(FileAuth(env.root), file).exists()

  fun _system_status(command: String box): I32 =>
    let status = @system(command.cstring())
    if status > 255 then status / 256 else status end

  fun _shell_quote(value: String box): String =>
    let out = String
    out.append("'")
    for ch in value.values() do
      if ch == 39 then out.append("'\\''") else out.push(ch) end
    end
    out.append("'")
    out.clone()
