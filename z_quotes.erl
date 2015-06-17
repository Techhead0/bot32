-module(z_quotes).
-compile(export_all).

-include("definitions.hrl").

get_commands() ->
	[
		{"quote", fun quote/5, user},
		{"quotename", fun quotename/5, user},
		{"quoteword", fun quoteword/5, user},
		{"addquote",  fun addquote/5, user},
		{"makequote", fun addquote/5, user},
		{"save_quote", fun savequote/5, host},
		{"load_quote", fun loadquote/5, host},
		{"delquote",    gen_delquote(fun gen_genmatch/1  ), admin},
		{"delquote_c",  gen_delquote(fun gen_catmatch/1  ), admin},
		{"delquote_e",  gen_delquote(fun gen_exmatch/1   ), admin},
		{"delquote_ce", gen_delquote(fun gen_excatmatch/1), admin},
		{"remquote",    gen_delquote(fun gen_genmatch/1  ), admin},
		{"remquote_c",  gen_delquote(fun gen_catmatch/1  ), admin},
		{"remquote_e",  gen_delquote(fun gen_exmatch/1   ), admin},
		{"remquote_ce", gen_delquote(fun gen_excatmatch/1), admin}

	].

get_data(#state{moduledata=M}) ->
	case orddict:find(z_quotes, M) of
		{ok, Value} -> Value;
		error -> []
	end.

set_data(S=#state{moduledata=M}, Data) ->
	S#state{moduledata=orddict:store(z_quotes, Data, M)}.

store_data(Data) ->
	bot ! {setkey, {z_quotes, Data}},
	ok.

initialise(T) -> set_data(T, load_quotes()).

deinitialise(T) ->
	save_quotes(get_data(T)),
	T#state{moduledata=orddict:erase(z_quotes, T#state.moduledata)}.

%

quote(_, ReplyTo, Ping, Params, State=#state{}) ->
	{irc, {msg, {ReplyTo, [Ping, get_quote(string:strip(string:to_lower(string:join(Params, " "))), get_data(State))]}}}.

quotename(_, ReplyTo, Ping, Params, State=#state{}) ->
	{irc, {msg, {ReplyTo, [Ping, get_quote_name(string:strip(string:to_lower(string:join(Params, " "))), get_data(State))]}}}.

quoteword(_, ReplyTo, Ping, Params, State=#state{}) ->
	{irc, {msg, {ReplyTo, [Ping, get_quote_word(string:strip(string:join(Params, " ")), get_data(State))]}}}.

addquote(_, ReplyTo, Ping, [], _) ->
	{irc, {msg, {ReplyTo, [Ping, "Please provide a category and a quote."]}}};
addquote(_, ReplyTo, Ping, [_], _) ->
	{irc, {msg, {ReplyTo, [Ping, "Please provide a quote."]}}};
addquote(_, ReplyTo, Ping, Params, State=#state{}) ->
	{Reply, Data} = add_quote(string:to_lower(hd(Params)), string:strip(string:join(tl(Params), " ")), get_data(State)),
	save_quotes(Data),
	store_data(Data),
	{irc, {msg, {ReplyTo, [Ping, Reply]}}}.

savequote(_, ReplyTo, Ping, _, State=#state{}) ->
	save_quotes(get_data(State)),
	{irc, {msg, {ReplyTo, [Ping, "Saved quotes."]}}}.

loadquote(_, ReplyTo, Ping, _, _) ->
	store_data(load_quotes()),
	{irc, {msg, {ReplyTo, [Ping, "Loaded quotes."]}}}.

gen_genmatch(Params) ->
	Quot = string:to_lower(string:join(Params, " ")),
	fun({_,Q}) -> string:str(string:to_lower(Q), Quot) /= 0 end.

gen_exmatch(Params) ->
	Quot = string:to_lower(string:join(Params, " ")),
	fun({_,Q}) -> string:to_lower(Q) == Quot end.

gen_catmatch(Params) ->
	Cat = string:to_lower(hd(Params)),
	General = gen_genmatch(tl(Params)),
	fun(T={C,_}) -> Cat == C andalso General(T) end.

gen_excatmatch(Params) ->
	Cat = string:to_lower(hd(Params)),
	General = gen_exmatch(tl(Params)),
	fun(T={C,_}) -> Cat == C andalso General(T) end.

gen_delquote(Func) ->
	fun(_, ReplyTo, Ping, [], _) -> {irc, {msg, {ReplyTo, [Ping, "Provide a quote to delete!"]}}};
	   (_, ReplyTo, Ping, Params, State=#state{}) ->
		case remove_quote(Func(Params), get_data(State)) of
			no_match -> {irc, {msg, {ReplyTo, [Ping, "No matching quotes found."]}}};
			{multi_match, Num} -> {irc, {msg, {ReplyTo, [Ping, integer_to_list(Num), " matching quotes found."]}}};
			NewData ->
				save_quotes(NewData),
				store_data(NewData),
				{irc, {msg, {ReplyTo, [Ping, "Quote deleted."]}}}
		end
	end.

%

get_quote([], Quotes) -> pick_quote(Quotes);
get_quote(String, Quotes) ->
	Matching = lists:filter(fun({Cat, Q}) ->
			string:str(string:to_lower(Q), String) /= 0 orelse Cat == String
		end, Quotes),
	pick_quote(Matching).

remove_quote(MatchFunc, Quotes) ->
	case lists:filter(MatchFunc, Quotes) of
		[] -> no_match;
		[Quote] -> lists:delete(Quote, Quotes);
		Q -> {multi_match, length(Q)}
	end.

get_quote_name([], _) -> "Please supply a username to quote from.";
get_quote_name(String, Quotes) ->
	Matching = lists:filter(fun({Cat, _}) -> lists:prefix(String, Cat) end, Quotes),
	pick_quote(Matching).

get_quote_word([], _) -> "Please supply a word or words to find quotes for.";
get_quote_word(String, Quotes) ->
	Regexed = lists:foldl(fun([F,R], Str) -> re:replace(Str, F, R) end, String,
		[
			["\\\\","\\\\\\\\"],
			["\\^", "\\\\^"],
			["\\$", "\\\\$"],
			["\\.", "\\\\."],
			["\\[", "\\\\["],
			["\\]", "\\\\]"],
			["\\(", "\\\\("],
			["\\)", "\\\\)"],
			["\\?", "\\\\?"],
			["\\*", "\\\\*"],
			["\\+", "\\\\+"],
			["\\{", "\\\\{"],
			["\\-", "\\\\-"]
		]),
	Matching = lists:filter(fun({_,Q}) ->
			re:run(Q, ["\\W",Regexed,"\\W"], [{capture, none}, caseless]) == match
		end, Quotes),
	pick_quote(Matching).

pick_quote([]) -> "No matching quotes.";
pick_quote(Q) ->
	{Cat, Quote} = lists:nth(random:uniform(length(Q)), Q),
	["\"", Quote, "\" - ",Cat].

add_quote(Category, String, Quotes) ->
	LowerString = string:to_lower(String),
	case length(lists:filter(fun({_, Q}) ->
				string:to_lower(Q) == LowerString
			end, Quotes)) of
		0 -> {"Quote added.", [{Category, String} | Quotes]};
		_ -> {"Quote is already listed.", Quotes}
	end.

load_quotes() ->
	case file:consult("quotes.crl") of
		{ok, [Term]} ->
			common:debug("QUOTE", "Loaded."),
			Term;
		{error, E} ->
			common:debug("QUOTE", "Creating new (error ~p).", [E]),
			[]
	end.

save_quotes(Quotes) ->
	file:write_file("quotes.crl", io_lib:format("~p.~n", [Quotes])),
	common:debug("QUOTE", "Saved.").

