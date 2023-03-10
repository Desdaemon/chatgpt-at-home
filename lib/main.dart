import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'searchable_list_view.dart';
import 'package:eventsource/eventsource.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final sp = await SharedPreferences.getInstance();
    apiKey = sp.getString(apiKeyId) ?? const String.fromEnvironment(apiKeyId);
  } catch (err, st) {
    debugPrint('failed to retrieve API key: $err');
    debugPrint('Stack trace: $st');
  }
  runApp(const ChatBotApp());
}

Future<SharedPreferences> get sp => SharedPreferences.getInstance();

var apiKey = '';
const apiKeyId = 'openaiApiKey';
const material3 = bool.fromEnvironment('material3', defaultValue: true);
const user = 'chatgpt@home';
const done = '[DONE]';
Map<String, String> get requestHeaders =>
    {'content-type': 'application/json', 'authorization': 'Bearer $apiKey'};

final completionEndpoint = Uri.https('api.openai.com', '/v1/chat/completions');

void openLinks(String _, String? href, String title) async {
  if (href != null) {
    await launchUrl(
      Uri.parse(href),
      webOnlyWindowName: title,
      mode: LaunchMode.externalApplication,
    );
  }
}

/// see [docs](https://platform.openai.com/docs/api-reference/chat/create)
Stream<String> chat(
  List<ChatMessage> messages, {
  String model = 'gpt-3.5-turbo',
  void Function(dynamic)? onError,
}) async* {
  final request = jsonEncode({
    'model': model,
    'stream': true,
    'user': user,
    'messages': [
      for (final message in messages)
        if (message.role != Role.system)
          {'role': message.role.api, 'content': message.text}
    ]
  });
  final events = await EventSource.connect(
    completionEndpoint,
    method: 'POST',
    headers: requestHeaders,
    body: request,
  ).catchError((error) {
    if (error is EventSourceSubscriptionException) {
      debugPrint('failed to chat: ${error.message}');
    }
    onError?.call(error);

    throw error;
  });
  var role = 'assistant';
  await for (final event in events) {
    if (event.data == done) break;

    final data = jsonDecode(event.data!);
    final Map<String, dynamic> delta = data['choices'][0]['delta'];
    if (delta.containsKey('role')) {
      role = delta['role'];
      debugPrint('talking as: $role');
    } else if (delta.containsKey('content')) {
      yield delta['content'] as String;
    }
  }
}

class ChatBotApp extends StatelessWidget {
  const ChatBotApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ChatGPT@Home',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.light(useMaterial3: material3),
      darkTheme: ThemeData.dark(useMaterial3: material3),
      home: const ChatScreen(),
    );
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _textController = TextEditingController();

  // Define the list of chat messages
  final List<ChatMessage> _messages = [];
  final stt = SpeechToText();
  LocaleName? currentLocale;
  String? interim;
  List<LocaleName> locales = [];

  var sttInitialized = false;

  @override
  void initState() {
    super.initState();

    (() async {
      final initialized =
          await stt.initialize(debugLogging: kDebugMode).catchError((err) {
        debugPrint('Could not initialize speech-to-text: $err');
        return false;
      });

      setState(() => sttInitialized = initialized);
      if (initialized) {
        final locales = await stt.locales();
        setState(() => this.locales = locales);
      }
    })();
  }

  void _onSelectLanguage() async {
    final choice = await showDialog<LocaleName>(
      context: context,
      builder: (context) {
        String? needle;
        Function(Function()) setState = (_) {};

        return Card(
          child: Center(
            child: Column(children: [
              TextFormField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search dictation locales',
                ),
                onChanged: (input) {
                  setState(() {
                    needle = input;
                  });
                },
              ),
              Expanded(
                child: StatefulBuilder(builder: (context, $setState) {
                  // HACK: setState escapes builder
                  setState = $setState;
                  return SearchableListView.builder(
                    searching: needle != null,
                    onFilter: (i) => locales[i]
                        .name
                        .toLowerCase()
                        .contains(needle!.toLowerCase()),
                    itemCount: locales.length,
                    itemBuilder: (context, i) => ListTile(
                        title: Text(locales[i].name),
                        onTap: () => Navigator.pop(context, locales[i])),
                  );
                }),
              )
            ]),
          ),
        );
      },
    );
    if (choice != null) {
      setState(() {
        currentLocale = choice;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ChatGPT@Home'), actions: [
        if (locales.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.language),
            onPressed: _onSelectLanguage,
          ),
        IconButton(
          icon: const Icon(Icons.cleaning_services),
          onPressed: _onClearMessages,
        ),
        IconButton(
          icon: const Icon(Icons.settings),
          onPressed: _onOpenSettings,
        )
      ]),
      body: Column(children: [
        Flexible(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: CustomScrollView(
              reverse: true,
              slivers: [
                if (interim != null)
                  SliverToBoxAdapter(
                    child: ChatMessage(
                      text: interim!,
                      role: Role.assistant,
                    ),
                  ),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, index) => _messages[_messages.length - index - 1],
                    childCount: _messages.length,
                  ),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1.0),
        Container(
          decoration: BoxDecoration(color: Theme.of(context).cardColor),
          child: Builder(builder: _buildTextComposer),
        ),
      ]),
    );
  }

  Widget _buildTextComposer(BuildContext context) {
    final hasApiKey = apiKey.isNotEmpty;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Row(
        children: <Widget>[
          if (sttInitialized)
            IconButton(
              icon: const Icon(Icons.mic),
              onPressed: () async {
                var interim = '...';
                Function(Function()) setState = (_) {};
                final ctl = showBottomSheet(
                  context: context,
                  builder: (context) {
                    return StatefulBuilder(builder: (context, $setState) {
                      // HACK: setState escapes the builder.
                      setState = $setState;
                      return Card(
                        child: SizedBox(
                          height: 200,
                          width: double.infinity,
                          child: Center(
                            child: Text(
                              interim,
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                          ),
                        ),
                      );
                    });
                  },
                );
                stt.errorListener = (_) => ctl.close();
                await stt.listen(
                  cancelOnError: true,
                  listenMode: ListenMode.dictation,
                  localeId: currentLocale?.localeId,
                  onResult: (result) {
                    if (result.finalResult) {
                      stt.stop();
                      ctl.close();
                      addMessage(ChatMessage(
                        text: result.recognizedWords,
                        role: Role.user,
                      ));
                      return;
                    }

                    setState(() {
                      interim = result.recognizedWords;
                    });
                  },
                );
              },
            ),
          Expanded(
            child: TextField(
              controller: _textController,
              onSubmitted: _handleSubmitted,
              decoration: InputDecoration.collapsed(
                hintText: hasApiKey ? 'Ask me anything' : 'No API key set',
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.send),
            onPressed: !hasApiKey
                ? null
                : () => _handleSubmitted(_textController.text),
          ),
        ],
      ),
    );
  }

  void _handleSubmitted(String text) {
    _textController.clear();
    addMessage(ChatMessage(
      text: text,
      role: Role.user,
    ));
  }

  void addMessage(ChatMessage chatMessage) async {
    if (chatMessage.text.isEmpty) return;

    setState(() {
      _messages.add(chatMessage);
      interim = '';
    });

    void onError(err) {
      var message = err.toString();
      if (err is EventSourceSubscriptionException) {
        message = jsonDecode(err.message)['error']['message'];
      }

      setState(() {
        interim = null;
        _messages.add(ChatMessage(
          text: message,
          role: Role.system,
        ));
      });
    }

    await for (final delta in chat(_messages, onError: onError)) {
      setState(() {
        interim = interim! + delta;
      });
    }

    setState(() {
      _messages.add(ChatMessage(text: interim!, role: Role.assistant));
      interim = null;
    });
  }

  void _onClearMessages() {
    setState(() {
      _messages.clear();
    });
  }

  void _onOpenSettings() async {
    await showDialog(
      context: context,
      builder: (BuildContext context) {
        String newApiKey = apiKey;

        return AlertDialog(
          title: const Text('Set API Key'),
          content: TextFormField(
            initialValue: newApiKey,
            obscureText: true,
            decoration: const InputDecoration(hintText: 'Enter your API key'),
            onChanged: (value) => newApiKey = value,
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.pop(context);
              },
            ),
            TextButton(
              child: const Text('Save'),
              onPressed: () async {
                await (await sp).setString(apiKeyId, apiKey = newApiKey);
                setState(() {
                  if (mounted) Navigator.pop(context);
                });
              },
            ),
          ],
        );
      },
    );
  }
}

enum Role {
  user('user'),
  assistant('assistant'),
  system('system');

  final String api;
  const Role(this.api);
}

class ChatMessage extends StatelessWidget {
  const ChatMessage({
    super.key,
    required this.text,
    required this.role,
  });

  final String text;
  final Role role;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget body = MarkdownBody(
      data: text,
      selectable: true,
      onTapLink: openLinks,
      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
        blockquote: theme.textTheme.bodyMedium!.copyWith(
          color: theme.colorScheme.onSurface,
        ),
        blockquoteDecoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border.all(
            color: theme.colorScheme.secondaryContainer,
          ),
        ),
      ),
    );
    final isUserMessage = role == Role.user;
    if (role == Role.system) {
      body = ListTile(
        leading: const Icon(Icons.warning),
        tileColor: theme.colorScheme.errorContainer,
        title: body,
      );
    }
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (role != Role.system)
            Container(
              margin: const EdgeInsets.only(right: 16.0),
              child: CircleAvatar(
                child: Text(isUserMessage ? 'U' : 'C'),
              ),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (role != Role.system)
                  Text(
                    isUserMessage ? 'You' : 'ChatGPT',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                Container(margin: const EdgeInsets.only(top: 5.0), child: body),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
