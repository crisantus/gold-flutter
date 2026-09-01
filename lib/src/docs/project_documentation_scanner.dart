import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:path/path.dart' as p;

import '../project/project_inspection.dart';
import 'project_documentation.dart';

final class ProjectDocumentationScanner {
  const ProjectDocumentationScanner();

  Future<ProjectDocumentation> scan(ProjectInspection project) async {
    final routes = <RouteDocumentation>[];
    final models = <ModelDocumentation>[];
    final unknown = <String>[];
    final layers = <String>{};
    final lib = Directory(p.join(project.root.path, 'lib'));
    if (await lib.exists()) {
      for (final layer in const [
        'core',
        'domain',
        'data',
        'business',
        'presentation',
      ]) {
        if (await Directory(p.join(lib.path, layer)).exists()) {
          layers.add(layer);
        }
      }
      await _scanRoutes(project, lib, routes, unknown);
    }
    final modelRoot = Directory(p.join(lib.path, 'domain', 'models'));
    if (await modelRoot.exists()) {
      await _scanModels(project, modelRoot, models, unknown);
    }
    return ProjectDocumentation.normalized(
      projectName: project.projectName,
      dependencies: project.dependencies,
      assets: project.assets,
      layers: layers,
      routes: routes,
      models: models,
      unknownFacts: unknown,
      generatedAtVersion: '0.2.0-dev',
    );
  }

  Future<void> _scanModels(
    ProjectInspection project,
    Directory directory,
    List<ModelDocumentation> models,
    List<String> unknown,
  ) async {
    await for (final entity in directory.list(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final relative = _relative(project, entity);
      final parsed = parseString(
        content: await entity.readAsString(),
        path: entity.path,
        throwIfDiagnostics: false,
      );
      if (parsed.errors.isNotEmpty) {
        unknown.add('$relative: model source could not be parsed');
        continue;
      }
      for (final declaration
          in parsed.unit.declarations.whereType<ClassDeclaration>()) {
        final fields = <ModelFieldDocumentation>[];
        for (final member
            in declaration.members.whereType<FieldDeclaration>()) {
          if (!member.fields.isFinal || member.isStatic) continue;
          final type = member.fields.type?.toSource() ?? 'dynamic';
          for (final variable in member.fields.variables) {
            fields.add(
              ModelFieldDocumentation(
                name: variable.name.lexeme,
                type: type,
              ),
            );
          }
        }
        models.add(
          ModelDocumentation(
            name: declaration.name.lexeme,
            fields: List.unmodifiable(fields),
          ),
        );
      }
    }
  }

  Future<void> _scanRoutes(
    ProjectInspection project,
    Directory directory,
    List<RouteDocumentation> routes,
    List<String> unknown,
  ) async {
    await for (final entity in directory.list(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = await entity.readAsString();
      if (!source.contains('AutoRoute')) continue;
      final parsed = parseString(
        content: source,
        path: entity.path,
        throwIfDiagnostics: false,
      );
      final relative = _relative(project, entity);
      if (parsed.errors.isNotEmpty) {
        unknown.add('$relative: route source could not be parsed');
        continue;
      }
      final visitor = _AutoRouteVisitor(relative);
      parsed.unit.accept(visitor);
      routes.addAll(visitor.routes);
      unknown.addAll(visitor.unknown);
    }
  }

  static String _relative(ProjectInspection project, File file) =>
      p.posix.joinAll(p.split(p.relative(file.path, from: project.root.path)));
}

final class _AutoRouteVisitor extends RecursiveAstVisitor<void> {
  _AutoRouteVisitor(this.relativePath);

  final String relativePath;
  final List<RouteDocumentation> routes = [];
  final List<String> unknown = [];

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (node.constructorName.type.name2.lexeme != 'AutoRoute') {
      super.visitInstanceCreationExpression(node);
      return;
    }
    _record(node.argumentList);
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.target == null && node.methodName.name == 'AutoRoute') {
      _record(node.argumentList);
    }
    super.visitMethodInvocation(node);
  }

  void _record(ArgumentList argumentList) {
    final named = <String, Expression>{};
    for (final argument
        in argumentList.arguments.whereType<NamedExpression>()) {
      named[argument.name.label.name] = argument.expression;
    }
    final pageName = _pageName(named['page']);
    if (pageName == null) {
      unknown.add('$relativePath: dynamic AutoRoute page');
      return;
    }
    final pathExpression = named['path'];
    final path = pathExpression == null
        ? null
        : pathExpression is SimpleStringLiteral
            ? pathExpression.value
            : null;
    if (pathExpression != null && path == null) {
      unknown.add('$relativePath: dynamic path for $pageName');
    }
    final initial = named['initial'];
    routes.add(
      RouteDocumentation(
        name: pageName,
        path: path,
        isInitial: initial is BooleanLiteral && initial.value,
      ),
    );
  }

  static String? _pageName(Expression? expression) {
    if (expression is PropertyAccess) {
      return expression.target?.toSource();
    }
    if (expression is PrefixedIdentifier &&
        expression.identifier.name == 'page') {
      return expression.prefix.name;
    }
    return null;
  }
}
