import 'dart:convert';
import 'dart:io';

import 'package:creator/creator.dart' hide AsyncData;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:isar/isar.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:source_parser/creator/source.dart';
import 'package:source_parser/provider/source.dart';
import 'package:source_parser/schema/isar.dart';
import 'package:source_parser/schema/source.dart';
import 'package:source_parser/util/message.dart';
import 'package:source_parser/widget/loading.dart';
import 'package:source_parser/widget/source_tag.dart';

class BookSourceList extends StatefulWidget {
  const BookSourceList({super.key});

  @override
  State<BookSourceList> createState() => _BookSourceListState();
}

class _BookSourceListState extends State<BookSourceList> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            onPressed: importSource,
            icon: const Icon(Icons.more_horiz_outlined),
          )
        ],
        title: const Text('书源管理'),
      ),
      body: Consumer(
        builder: (context, ref, child) {
          final provider = ref.watch(sourcesProvider);
          List<Source> sources = switch (provider) {
            AsyncData(:final value) => value,
            _ => [],
          };
          if (sources.isEmpty) return const Center(child: Text('空空如也'));
          return ListView.builder(
            itemCount: sources.length,
            itemBuilder: (context, index) {
              return _SourceTile(
                key: ValueKey('source-$index'),
                source: sources[index],
                onTap: editSource,
              );
            },
            itemExtent: 56,
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: createSource,
        child: const Icon(Icons.add_outlined),
      ),
    );
  }

  void importSource() async {
    showModalBottomSheet(
      builder: (_) {
        return ListView(children: [
          ListTile(
            title: const Text('网络导入'),
            onTap: importNetworkSource,
          ),
          Consumer(builder: ((context, ref, child) {
            return ListTile(
              title: const Text('本地导入'),
              onTap: () => importLocalSource(ref),
            );
          })),
          ListTile(
            title: const Text('导出所有书源'),
            onTap: () => exportSource(context),
          ),
          const Divider(height: 1, thickness: 0.5),
          ListTile(
            title: const Text('校验书源'),
            onTap: () => exportSource(context),
          ),
        ]);
      },
      context: context,
    );
  }

  void importNetworkSource() async {
    final router = GoRouter.of(context);
    router.pop();
    showModalBottomSheet(
      builder: (_) => Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            Consumer(builder: (context, ref, child) {
              return TextField(
                decoration: const InputDecoration(hintText: '导入网络书源'),
                onSubmitted: (value) =>
                    confirmImporting(ref, value, from: 'network'),
              );
            }),
            const SizedBox(height: 8),
            const SelectableText('目前仅支持GitHub仓库中文件的原始地址。'),
          ],
        ),
      ),
      context: context,
    );
    // router.pop();
  }

  void importLocalSource(WidgetRef ref) async {
    final router = GoRouter.of(context);
    router.pop();
    final result = await FilePicker.platform.pickFiles();
    if (result != null) {
      final file = File(result.files.single.path!);
      final content = await file.readAsString();
      confirmImporting(ref, content, from: 'local');
    }
  }

  void confirmImporting(
    WidgetRef ref,
    String value, {
    String from = 'local',
  }) async {
    final router = Navigator.of(context);
    if (from == 'network') {
      router.pop();
    }
    showDialog(
      barrierDismissible: false,
      builder: (context) {
        return const UnconstrainedBox(
          child: SizedBox(
            height: 160,
            width: 160,
            child: Dialog(
              insetPadding: EdgeInsets.zero,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  LoadingIndicator(),
                  SizedBox(height: 16),
                  Text('正在加载'),
                ],
              ),
            ),
          ),
        );
      },
      context: context,
    );
    final message = Message.of(context);
    try {
      final notifier = ref.read(sourcesProvider.notifier);
      final (newSources, oldSources) = await notifier.importSources(
        from: from,
        value: value,
      );
      router.pop();
      if (oldSources.isNotEmpty) {
        final keepButton = Consumer(builder: (context, ref, child) {
          return TextButton(
            onPressed: () => confirm(ref, newSources, oldSources),
            child: const Text('保持原有'),
          );
        });
        final overrideButton = Consumer(builder: (context, ref, child) {
          return TextButton(
            onPressed: () => confirm(
              ref,
              newSources,
              oldSources,
              override: true,
            ),
            child: const Text('直接覆盖'),
          );
        });
        showDialog(
          builder: (_) {
            return AlertDialog(
              actions: [keepButton, overrideButton],
              title: Text('发现${oldSources.length}个同名书源书源'),
            );
          },
          context: context,
        );
      } else {
        await notifier.confirmImport(newSources, oldSources);
      }
    } catch (error) {
      router.pop();
      message.show(error.toString());
    }
  }

  void confirm(
    WidgetRef ref,
    List<Source> newSources,
    List<Source> oldSources, {
    bool override = false,
  }) async {
    final router = Navigator.of(context);
    final notifier = ref.read(sourcesProvider.notifier);
    await notifier.confirmImport(newSources, oldSources, override: override);
    router.pop();
  }

  void exportSource(BuildContext context) async {
    final router = Navigator.of(context);
    router.pop();
    final sources = await isar.sources.where().findAll();
    final json = sources.map((source) {
      final string = source.toJson();
      string.remove('id');
      return string;
    }).toList();
    final directory = await getApplicationDocumentsDirectory();
    final filePath = path.join(directory.path, 'sources.json');
    await File(filePath).writeAsString(jsonEncode(json));
    Share.shareXFiles([XFile(filePath)], subject: 'sources.json');
  }

  void editSource(int id) async {
    final ref = context.ref;
    final navigator = GoRouter.of(context);
    final source = await isar.sources.filter().idEqualTo(id).findFirst();
    ref.set(currentSourceCreator, source);
    navigator.push('/book-source/information/$id');
  }

  void createSource() {
    context.ref.set(currentSourceCreator, Source());
    context.push('/book-source/create');
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({Key? key, required this.source, this.onTap})
      : super(key: key);

  final Source source;
  final void Function(int)? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    var onBackground = colorScheme.onBackground;
    if (!source.enabled) {
      onBackground = onBackground.withOpacity(0.8);
    }
    final primary = colorScheme.primary;
    return InkWell(
      onTap: handleTap,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: DefaultTextStyle.merge(
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: onBackground),
                child: Text.rich(
                  TextSpan(
                    text: source.name,
                    children: [WidgetSpan(child: SourceTag(source.comment))],
                  ),
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
            IconTheme.merge(
              data: IconThemeData(color: primary, size: 12),
              child: Row(
                children: [
                  if (source.enabled) const Icon(Icons.search_outlined),
                  if (source.exploreEnabled == true) const SizedBox(width: 8),
                  if (source.exploreEnabled == true)
                    const Icon(Icons.explore_outlined)
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void handleTap() {
    onTap?.call(source.id);
  }
}
