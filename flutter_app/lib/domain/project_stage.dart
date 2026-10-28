/// Project lifecycle stage (stored in [ProjectDocumentation.stage]).
enum ProjectStage {
  design('Проектирование', 'Геометрия, раскладки, материалы'),
  install('Монтаж', 'Работы на объекте, скрытые работы'),
  documentation('Документация', 'Исполнительные схемы, ведомости, акты'),
  handover('Сдача', 'Комплект готов к передаче заказчику');

  const ProjectStage(this.labelRu, this.hintRu);

  final String labelRu;
  final String hintRu;

  static ProjectStage parse(String? raw) => ProjectStage.values.firstWhere(
        (s) => s.name == raw,
        orElse: () => ProjectStage.design,
      );

  ProjectStage? get next => switch (this) {
        ProjectStage.design => ProjectStage.install,
        ProjectStage.install => ProjectStage.documentation,
        ProjectStage.documentation => ProjectStage.handover,
        ProjectStage.handover => null,
      };
}

extension ProjectStageProgress on ProjectStage {
  double get progress => switch (this) {
        ProjectStage.design => 0.25,
        ProjectStage.install => 0.5,
        ProjectStage.documentation => 0.75,
        ProjectStage.handover => 1.0,
      };
}
