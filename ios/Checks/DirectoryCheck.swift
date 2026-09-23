let decoder = JSONDecoder()
decoder.keyDecodingStrategy = .convertFromSnakeCase
for path in CommandLine.arguments.dropFirst() {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let directory = try decoder.decode(CaucusDirectory.self, from: data)
    precondition(directory.groups.count == 5 && directory.skippedEntries == 0, "Invalid live directory")
    for group in directory.groups { precondition(!group.members.isEmpty, "Empty home destination") }
    var damaged = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    var groups = damaged["groups"] as! [[String: Any]]
    var members = groups[0]["members"] as! [[String: Any]]
    members[0].removeValue(forKey: "member"); groups[0]["members"] = members; damaged["groups"] = groups
    let recovered = try decoder.decode(CaucusDirectory.self, from: JSONSerialization.data(withJSONObject: damaged))
    precondition(recovered.skippedEntries == 1 && recovered.groups.count == 5, "One invalid row must not break Home")
    print("Validated all Home destinations and malformed-entry recovery:", path)
}
