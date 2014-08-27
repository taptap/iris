-module(iris_plugin).
-callback start(Config :: map(),   %% jid_config map (from data_structures dir)
                From :: pid()) ->  %% jid_worker pid
    term().

-callback process_message(Message :: map(),   %% message map (also of data structures kind)
                          Config :: map()) -> %% jid_config
    term().
