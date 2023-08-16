import 'package:creator/creator.dart';
import 'package:creator_watcher/creator_watcher.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:isar/isar.dart';
import 'package:source_parser/creator/source.dart';
import 'package:source_parser/main.dart';
import 'package:source_parser/schema/source.dart';
import 'package:source_parser/util/parser.dart';

class BookSourceList extends StatelessWidget {
  const BookSourceList({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            onPressed: () => importSource(context),
            icon: const Icon(Icons.cloud_upload_outlined),
          )
        ],
        title: const Text('书源管理'),
      ),
      body: EmitterWatcher<List<Source>>(
        builder: (context, sources) {
          if (sources.isNotEmpty) {
            return ListView.builder(
              itemCount: sources.length,
              itemBuilder: (context, index) {
                return SourceTile(
                  key: ValueKey('source-$index'),
                  source: sources[index],
                  onTap: (id) => handleTap(context, id),
                );
              },
            );
          } else {
            return const Center(child: Text('空空如也'));
          }
        },
        emitter: sourcesEmitter,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/book-source/create'),
        child: const Icon(Icons.add_outlined),
      ),
    );
  }

  void importSource(BuildContext context) async {
    showModalBottomSheet(
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            TextField(
              decoration: const InputDecoration(hintText: '导入网络书源'),
              onSubmitted: (value) => confirmImporting(context, value),
            ),
            const SizedBox(height: 8),
            const SelectableText(
              '目前仅支持GitHub仓库中文件的原始地址，例如https://raw.githubuserconten'
              't.com/CalsRanna/RuleSample/master/rule.json',
            ),
          ],
        ),
      ),
    );
  }

  void confirmImporting(BuildContext context, String value) async {
    final router = Navigator.of(context);
    final ref = context.ref;
    var sources = await Parser().importNetworkSource(value);
    await isar.writeTxn(() async {
      await isar.sources.putAll(sources);
      sources = await isar.sources.where().findAll();
      ref.emit(sourcesEmitter, sources);
    });
    router.pop();
  }

  void handleTap(BuildContext context, int id) async {
    final ref = context.ref;
    final navigator = GoRouter.of(context);
    final source = await isar.sources.filter().idEqualTo(id).findFirst();
    ref.set(currentSourceCreator, source);
    navigator.push('/book-source/information/$id');
  }
}

class SourceTile extends StatelessWidget {
  const SourceTile({Key? key, required this.source, this.onTap})
      : super(key: key);

  final Source source;
  final void Function(int)? onTap;

  @override
  Widget build(BuildContext context) {
    var color = Colors.black;
    if (!source.enabled) {
      color = Colors.grey;
    }

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
                style: TextStyle(color: color),
                child: Text(source.name, style: const TextStyle(fontSize: 16)),
              ),
            ),
            IconTheme.merge(
              data: IconThemeData(
                color: Theme.of(context).primaryColor,
                size: 12,
              ),
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