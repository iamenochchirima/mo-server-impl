import Server "./server";
import Blob "mo:base/Blob";
import CertifiedCache "mo:certified-cache";
import Debug "mo:base/Debug";
import Hash "mo:base/Hash";
import HM "mo:base/HashMap";
import HashMap "mo:StableHashMap/FunctionalStableHashMap";
import Int "mo:base/Int";
import Iter "mo:base/Iter";
import serdeJson "mo:serde/JSON";
import Option "mo:base-0.7.3/Option";
import Text "mo:base/Text";
import Time "mo:base/Time";
import Trie "mo:base/Trie";
import Nat "mo:base/Nat";
import Buffer "mo:base/Buffer";
import TrieMap "mo:base/TrieMap";
import List "mo:base/List";
import Result "mo:base/Result";
import AssocList "mo:base/AssocList";
import Error "mo:base/Error";
import Nat32 "mo:base/Nat32";
import Type "mo:candid/Type";
import Types "types";

shared ({ caller = initializer }) actor class ServerTest() = this {
  type Response = Server.Response;
  type HttpRequest = Server.HttpRequest;
  type HttpResponse = Server.HttpResponse;

  type User = Types.User;

  type FileObject = {
    filename : Text;
  };

  // User state
  private stable var usersState : [(Text, User)] = [];
  var users : TrieMap.TrieMap<Text, User> = TrieMap.fromEntries(usersState.vals(), Text.equal, Text.hash);

  // State upgrade functions
  system func preupgrade() {
    cacheStorage := server.entries();
    usersState := Iter.toArray(users.entries());
  };

  system func postupgrade() {
    ignore server.cache.pruneAll();
    usersState := [];
  };

  public shared query func get_users() : async [User] {
    Iter.toArray(users.vals());
  };

  stable var cacheStorage : Server.SerializedEntries = ([], [], [initializer]);

  var server = Server.Server({
    serializedEntries = cacheStorage;
  });

  public query func http_request(req : HttpRequest) : async HttpResponse {
    server.http_request(req);
  };

  public func http_request_update(req : HttpRequest) : async HttpResponse {
    server.http_request_update(req);
  };

  public func invalidate_cache() : async () {
    server.empty_cache();
  };

  func processFileObject(data : Text) : ?FileObject {
    let blob = serdeJson.fromText(data);
    from_candid (blob);
  };

  func processRequest(data : Text) : ?User {
    let blob = serdeJson.fromText(data);
    from_candid (blob);
  };

  server.post(
    "/add-user",
    func(req, res) : Response {
      let body = req.body;
      switch body {
        case null {
          Debug.print("body not parsed");
          res.send({
            status_code = 400;
            headers = [];
            body = Text.encodeUtf8("Invalid JSON");
            streaming_strategy = null;
            cache_strategy = #noCache;
          });
        };
        case (?body) {
          let bodyText = body.text();
          Debug.print("Request body:" # debug_show (body.text()));
          Debug.print(bodyText);
          let user = processRequest(bodyText);
          switch (user) {
            case null {
              Debug.print("user not parsed");
              res.send({
                status_code = 400;
                headers = [];
                body = Text.encodeUtf8("Invalid JSON");
                streaming_strategy = null;
                cache_strategy = #noCache;
              });
            };
            case (?user) {
              users.put(user.username, user);
              res.json({
                status_code = 201;
                body = "{ \"response\": \"ok\" }";
                cache_strategy = #noCache;
              });
            };
          };
        };
      };
    },
  );

  server.get(
    "/get-users",
    func(req, res) : Response {
      var counter = 0;

      var rowJson = "{ ";
      for (user in users.vals()) {
        rowJson := rowJson # "\"" # Nat.toText(counter) # "\": { \"username\": \"" # (user.username) # "\", \"firstname\": \"" # user.firstname # "\", \"lastname\": \"" # user.lastname # "\", \"email\": \"" # user.email # "\" }, ";
        counter += 1;
      };
      rowJson := Text.trimEnd(rowJson, #text ", ");
      rowJson := rowJson # " }";

      res.json({
        status_code = 200;
        body = rowJson;
        cache_strategy = #noCache;
      });
    },
  );

  server.get(
    "/get-user",
    func(req, res) : Response {
      let body = req.body;
      switch (body) {
        case null {
          res.json({
            status_code = 400;
            body = "{ \"response\": \"username not provided\" }";
            cache_strategy = #noCache;
          });
        };
        case (?body) {
          let bodyText = body.text();
          let val = processRequest(bodyText);
          Debug.print("Request body:" # debug_show (body.text()));
          let username = "iamenochchirima";
          let user = users.get(username);
          switch (user) {
            case null {
              res.json({
                status_code = 404;
                body = "{ \"response\": \"user not found\" }";
                cache_strategy = #noCache;
              });
            };
            case (?user) {
              res.json({
                status_code = 200;
                body = "{ \"response\": \"ok\", \"user\": { \"username\": \"" # (user.username) # "\", \"firstname\": \"" # user.firstname # "\", \"lastname\": \"" # user.lastname # "\", \"email\": \"" # user.email # "\" } }";
                cache_strategy = #noCache;
              });
            };
          };
        };
      };
    },
  );
};
