/// Lets the app adjust what a server answers before any API reads it, for
/// display-only overrides that must reach every screen at once (Sunfin's
/// library nicknames). It edits the decoded JSON in place and must leave
/// anything it doesn't recognise alone; nothing it does goes back to the
/// server.
typedef ServerResponseRewriter = void Function(Object? data);

/// Set once by the app; null leaves every response untouched.
ServerResponseRewriter? serverResponseRewriter;
