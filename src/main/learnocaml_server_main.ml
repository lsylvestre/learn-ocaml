(* This file is part of Learn-OCaml.
 *
 * Copyright (C) 2019 OCaml Software Foundation.
 * Copyright (C) 2016-2018 OCamlPro.
 *
 * Learn-OCaml is distributed under the terms of the MIT license. See the
 * included LICENSE file for details. *)

open Learnocaml_server_args
open Lwt.Infix

let signal_waiter =
  let waiter, wakener = Lwt.wait () in
  let handler signum =
    Format.eprintf "%s caught: stopping@."
      (if signum = Sys.sigint then "SIGINT" else
       if signum = Sys.sigterm then "SIGTERM" else
         "Signal");
    Lwt.wakeup_later wakener (128 - signum) in
  let _ = Lwt_unix.on_signal Sys.sigint handler in
  let _ = Lwt_unix.on_signal Sys.sigterm handler in
  waiter

let main o =
  Printf.printf "Learnocaml server v.%s starting on port %d\n%!"
    Learnocaml_api.version o.port;
  if o.base_url <> "" then
    Printf.printf "Base URL: %s\n%!" o.base_url;
  let rec run () =
    let minimum_duration = 15. in
    let t0 = Unix.time () in
    try
      Lwt_main.run @@ Lwt.pick [
        (Learnocaml_server.launch () >|= function true -> 0 | false -> 10);
        signal_waiter
      ]
    with Unix.Unix_error (err, fn, arg) ->
      Format.eprintf "SERVER CRASH in %s(%s):@ @[<hv 2>%s@]@."
        fn arg (Unix.error_message err);
      let dt = Unix.time () -. t0 in
      if dt < minimum_duration then
        (Format.eprintf "Live time was only %.0fs, aborting (<%fs)@."
           dt minimum_duration;
         exit 20)
      else
        (Format.eprintf "Server was live %.0f seconds. Respawning@." dt;
         run ())
  in
  exit (run ())

let man = [
  `S "DESCRIPTION";
  `P "This is the server for learn-ocaml. It is equivalent to running \
      $(b,learn-ocaml serve), but may be faster if compiled to native code. It \
      requires the learn-ocaml app to have been built using $(b,learn-ocaml \
      build) beforehand.";
  `S "SERVER OPTIONS";
  `S "AUTHORS";
  `P "Learn OCaml is written by OCamlPro. Its main authors are Benjamin Canou, \
      Çağdaş Bozman, Grégoire Henry and Louis Gesbert. It is licensed under \
      the MIT License.";
  `S "BUGS";
  `P "Bugs should be reported to \
      $(i,https://github.com/ocaml-sf/learn-ocaml/issues)";
]

let app_dir =
  let open Cmdliner.Arg in
  value & opt string "./www" & info ["app-dir"; "o"] ~docv:"DIR" ~doc:
    "Directory where the app has been generated by the $(b,learn-ocaml build) \
     command, and from where it will be served."

let base_url =
  let open Cmdliner.Arg in
  value & opt string "" &
    info ["base-url"] ~docv:"BASE_URL" ~env:(env_var "LEARNOCAML_BASE_URL") ~doc:
      "Set the base URL of the website. \
       Should not end with a trailing slash. \
       Currently, this has no effect on the backend - '$(b,learn-ocaml serve)'. \
       Mandatory for '$(b,learn-ocaml build)' if the site is not hosted in path '/', \
       which typically occurs for static deployment."

let main_cmd =
  Cmdliner.Term.(const main $ Learnocaml_server_args.term app_dir base_url),
  Cmdliner.Term.info
    ~man
    ~doc:"Learn-ocaml web-app manager"
    ~version:Learnocaml_api.version
    "learn-ocaml"

let () =
  match
    Cmdliner.Term.eval ~catch:false main_cmd
  with
  | exception Failure msg ->
      Printf.eprintf "[ERROR] %s\n" msg;
      exit 1
  | `Error _ -> exit 2
  | _ -> exit 0
