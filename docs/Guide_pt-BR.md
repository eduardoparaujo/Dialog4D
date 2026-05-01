# Dos fundamentos de diálogos FMX ao Dialog4D

**Version:** 1.0.1 — 2026-05-01

### Uma jornada conceitual pelos diálogos FMX, fluxo assíncrono e coordenação explícita de diálogos

---

Se você já escreveu código Delphi FMX que parecia síncrono no desktop e depois
precisou de outra forma de continuação no mobile — diálogos que retornam antes
do usuário responder, callbacks que carregam o resultado real, ou trechos de
código que precisam ir para dentro de um handler de fechamento — este texto é
para você.

O Delphi já fornece os mecanismos de diálogo com os quais a maioria das
aplicações FMX deveria começar: `ShowMessage`, `MessageDlg` e, especialmente,
`FMX.DialogService`. Essas APIs são práticas, oficialmente suportadas e
apropriadas para muitos cenários.

Este guia segue um caminho natural: começa por chamadas simples de diálogo no
FMX, observa como cada camada se comporta conforme os requisitos da aplicação
crescem, e só então introduz os conceitos que ajudam quando uma aplicação
precisa de coordenação adicional ao redor dos diálogos.

Ao final, o objetivo é que você entenda não apenas **como** usar diálogos no
Delphi FMX, mas **por que** cada camada da história dos diálogos existe. Como
culminação prática, você verá o **Dialog4D**, uma biblioteca complementar que
consolida essas preocupações em uma pequena API pública projetada para tornar as
decisões do usuário explícitas, observáveis, enfileiráveis e visualmente
consistentes dentro de uma superfície de diálogo renderizada em FMX.

> **Nota sobre o escopo.** Este guia percorre diferentes formas de trabalhar
> com diálogos no FMX, desde as APIs já disponíveis no Delphi até cenários em
> que a aplicação precisa de mais coordenação ao redor do fluxo de decisão.
> O Dialog4D aparece nesse contexto como uma camada complementar para diálogos
> renderizados em FMX, com foco em temas, fila por formulário, snapshots de
> configuração, telemetria e integração com threads de trabalho.

> **Nota sobre pré-requisitos.** Este guia foca em diálogos no FMX. Ele assume
> que você está confortável com métodos anônimos (closures), `TThread.Queue` /
> encaminhamento para a main thread, e vocabulário básico de threading. Se esses
> conceitos forem novos para você, o [guia conceitual do SafeThread4D](https://github.com/eduardoparaujo/SafeThread4D/blob/main/docs/Guide_pt-BR.md)
> cobre esses temas em detalhe e é um companheiro natural para este texto.

---

## Parte 1 — Por que diálogos precisam de ciclo de vida explícito

Um diálogo parece uma coisa pequena e inofensiva. O usuário clica em um botão,
uma janela aparece perguntando "Salvar alterações?", o usuário escolhe uma
resposta e a aplicação continua. Três linhas de código, nada demais.

O problema é que "a aplicação continua" não é um único conceito. São pelo menos
três coisas diferentes:

1. **A aplicação continua desenhando a interface.** Animações continuam
   rodando, timers continuam disparando, eventos continuam chegando.
2. **A aplicação continua o método que chamou o diálogo.** A linha logo após a
   chamada executa em algum momento.
3. **A aplicação continua o fluxo do usuário.** A próxima decisão, a próxima
   tela ou a próxima ação dependem da resposta.

Em um fluxo modal de estilo desktop tradicional, esses três conceitos podem
parecer a mesma coisa: o diálogo bloqueia o chamador, o usuário responde e a
execução continua na próxima linha.

Em código FMX multiplataforma, especialmente quando targets mobile estão
envolvidos, essa não é uma suposição universal segura. O FMX possui APIs cujo
comportamento depende da plataforma, do modo de apresentação selecionado e de a
chamada usar ou não uma forma baseada em callback. A lição prática é simples:

> **Não trate uma decisão do usuário como retorno síncrono de função a menos
> que o contrato da API e da plataforma suporte explicitamente esse uso.**

Depois que você aceita isso, todas as outras partes do design de diálogos ficam
mais fáceis de raciocinar.

---

## Parte 2 — `ShowMessage`: o diálogo mais simples e o primeiro modelo mental

A forma mais simples de diálogo é uma notificação:

```delphi
uses
  FMX.Dialogs;

procedure TForm1.btSaveClick(Sender: TObject);
begin
  SaveDocument;
  ShowMessage('Document saved.');
  CloseDocument;
end;
```

Você lê esse código de cima para baixo e pode esperar: salvar o documento,
mostrar uma confirmação e então fechar o documento.

Para notificações simples em estilo desktop, isso pode ser aceitável. Mas não é
um bom padrão geral para lógica de continuação multiplataforma. Uma notificação
não toma uma decisão significativa; ela apenas informa o usuário. Se o código
depois da notificação depende de o usuário dispensar a mensagem, a continuação
já está no lugar errado.

As APIs de diálogo orientadas a serviço no FMX deixam essa sensibilidade de
plataforma mais explícita. Por exemplo, a documentação oficial de
`TDialogService.ShowMessage` descreve o comportamento no desktop como síncrono e
o comportamento no mobile como assíncrono no modo orientado à plataforma. Isso
significa que código que assume "a linha depois do diálogo roda depois que o
usuário fecha" é frágil quando reutilizado em diferentes targets FMX.

Um modelo mental mais seguro é:

> **Uma notificação não é um ponto de continuação.**  
> **Se algo precisa acontecer depois que o usuário fecha um diálogo, use uma
> forma de API que ofereça um callback de fechamento.**

Essa mudança mental nos prepara para a próxima camada.

---

## Parte 3 — `MessageDlg`: mais botões, a mesma necessidade de cuidado

`MessageDlg` é o próximo passo. Ele permite fazer uma pergunta com vários
botões:

```delphi
uses
  FMX.Dialogs;

procedure TForm1.btCloseClick(Sender: TObject);
begin
  if MessageDlg('Save changes before closing?',
                TMsgDlgType.mtConfirmation,
                [TMsgDlgBtn.mbYes, TMsgDlgBtn.mbNo, TMsgDlgBtn.mbCancel],
                0) = mrYes then
    SaveDocument;

  CloseDocument;
end;
```

Essa forma é familiar para desenvolvedores Delphi. Ela se lê como um `if`
normal: se o usuário disse sim, salva; depois fecha.

Em código FMX moderno, porém, `MessageDlg` tem considerações importantes de
plataforma e sobrecarga. A documentação oficial marca `FMX.Dialogs.MessageDlg`
como deprecated e aponta os desenvolvedores para APIs de dialog service
assíncronas. Ela também documenta que o suporte bloqueante varia conforme a
plataforma e que chamadas baseadas em callback são não bloqueantes em
plataformas mobile.

A lição, portanto, não é "nunca use chamadas familiares de diálogo". A lição é
mais estreita e mais prática:

> **Fluxo de diálogo baseado em valor de retorno não é a base mais forte para
> lógica de decisão FMX multiplataforma.**

Quando a resposta do usuário realmente controla o que acontece em seguida, uma
forma baseada em callback é mais clara e mais segura.

É exatamente isso que o `FMX.DialogService` oferece.

---

## Parte 4 — `FMX.DialogService`: o caminho orientado a serviço recomendado

`FMX.DialogService` é a família oficial de serviços de diálogo do FMX. É o
ponto natural quando você quer uma forma de diálogo baseada em callback no FMX:

```delphi
uses
  FMX.DialogService;

procedure TForm1.btCloseClick(Sender: TObject);
begin
  TDialogService.MessageDialog(
    'Save changes before closing?',
    TMsgDlgType.mtConfirmation,
    [TMsgDlgBtn.mbYes, TMsgDlgBtn.mbNo, TMsgDlgBtn.mbCancel],
    TMsgDlgBtn.mbNo,
    0,
    procedure(const AResult: TModalResult)
    begin
      if AResult = mrYes then
        SaveDocument;

      CloseDocument;
    end);
end;
```

A forma é diferente. A decisão não é mais um valor de retorno testado em um
`if`; é um parâmetro entregue a um callback que executa depois que o usuário
fecha o diálogo. A continuação foi movida para dentro do callback, onde a
resposta é conhecida.

Isso é uma melhoria real. Para muitas aplicações, `FMX.DialogService` é a
ferramenta certa: ele faz parte do FMX, administra diferenças de plataforma e se
encaixa no modelo padrão de diálogos do FireMonkey.

O restante deste guia não é um argumento contra o `FMX.DialogService`. É uma
exploração do que acontece quando uma aplicação precisa de estrutura adicional
ao redor dos diálogos: enfileiramento por formulário, snapshots visuais no
momento da requisição, vocabulário de botões customizados por chamada,
fechamento programático, telemetria ou semântica de espera em thread de
trabalho.

### `PreferredMode`: aproximando expectativas de desktop e mobile

`TDialogService` expõe `PreferredMode` com três valores: `Platform`, `Async` e
`Sync`.

No modo `Platform`, plataformas desktop preferem comportamento síncrono e
plataformas mobile preferem comportamento assíncrono. `Sync` não é suportado no
Android. Esse é um sinal de design importante: se uma mesma base de código mira
desktop e mobile, um modelo mental assíncrono costuma ser o denominador comum
mais seguro.

Uma vez que você se compromete com a forma assíncrona, novas perguntas de
design aparecem.

---

## Parte 5 — Diálogo como roteador de fluxo

Depois que você aceita que chamadas de diálogo são assíncronas, passa a vê-las
de outra forma. Elas não são apenas perguntas; são **ramificações no fluxo da
aplicação**.

```delphi
procedure TForm1.PrepareToCloseDocument;
begin
  ValidateState;

  TDialogService.MessageDialog(
    'Save changes before closing?',
    TMsgDlgType.mtConfirmation,
    [TMsgDlgBtn.mbYes, TMsgDlgBtn.mbNo, TMsgDlgBtn.mbCancel],
    TMsgDlgBtn.mbYes,
    0,
    procedure(const AResult: TModalResult)
    begin
      case AResult of
        mrYes:    SaveAndClose;
        mrNo:     CloseWithoutSaving;
        mrCancel: ;  // user changed their mind
      end;
    end);
end;
```

O método valida o estado e faz uma pergunta. A continuação pertence ao callback
porque o callback é o lugar onde a resposta é conhecida.

Esse é um modelo mental útil:

> **Uma chamada de diálogo perto do final de um método age como um roteador de
> fluxo.**  
> O método inicia uma decisão, e a continuação flui por uma das ramificações do
> callback.

Isso funciona bem sob uma disciplina: a chamada de diálogo normalmente deve ser
a última instrução significativa do método. Código que depende da resposta do
usuário pertence ao callback.

```delphi
procedure TForm1.PrepareToCloseDocument;
begin
  ValidateState;

  TDialogService.MessageDialog(
    'Save changes before closing?',
    ...
    procedure(const AResult: TModalResult)
    begin
      if AResult = mrYes then
        SaveDocument;
    end);

  CloseDocument;  // Não é um ponto de continuação seguro em código multiplataforma.
end;
```

A regra é simples:

> **No FMX, trate o callback do diálogo como a continuação.**  
> O que precisa executar depois da decisão do usuário pertence ao callback.

---

## Parte 6 — Quando o roteador encontra concorrência: o problema da fila

O padrão "diálogo como roteador de fluxo" funciona bem quando uma única fonte
controla o fluxo. Aplicações reais frequentemente possuem várias fontes
independentes que podem requisitar diálogos:

- um clique de botão que pede confirmação;
- um timer avisando sobre expiração de sessão;
- uma resposta de servidor que informa um erro;
- uma thread de trabalho relatando uma condição excepcional.

Cada fonte pode pedir um diálogo em um momento diferente. Se a aplicação quer
que esses diálogos apareçam um por vez, em ordem, ela precisa de uma política de
coordenação.

`FMX.DialogService` não expõe em sua API pública uma fila FIFO por formulário no
estilo do Dialog4D. Isso não é uma falha; significa apenas que, se uma aplicação
precisa dessa regra específica de serialização, a aplicação deve fornecer essa
coordenação.

A coordenação em nível de aplicação normalmente envolve:

- rastrear se um diálogo já está ativo;
- armazenar requisições pendentes;
- despachar a próxima requisição depois que a ativa fecha;
- evitar corridas entre callbacks de fechamento e novas chegadas.

O Dialog4D incorpora essa política específica ao mecanismo:

> **Para cada formulário pai, o Dialog4D serializa requisições de diálogo por
> meio de uma fila FIFO.**

Uma requisição para o mesmo formulário espera atrás da ativa. Requisições para
formulários diferentes continuam independentes. Isso é útil quando múltiplas
fontes podem fazer perguntas na mesma tela e a aplicação quer apenas um diálogo
visível por vez naquele formulário.

A seção 5.1 do demo distribuído (`Queue burst`) mostra isso diretamente:
dispara seis diálogos a partir de uma worker `TTask.Run`, e a fila do Dialog4D
os apresenta um por vez.

---

## Parte 7 — Decisões sequenciais e callbacks aninhados

Mesmo dentro de uma única fonte de requisições de diálogo, decisões em múltiplas
etapas trazem seu próprio desafio de design.

Imagine um diálogo "Salvar antes de fechar?" onde cada resposta leva a um
caminho diferente:

- "Sim" → salva e depois pergunta "Fechar agora?"
- "Não" → pergunta "Tem certeza? Descartar não pode ser desfeito."
- "Cancelar" → volta ao editor, sem pergunta seguinte.

Escrito com diálogos baseados em callback, isso naturalmente se torna callbacks
aninhados:

```delphi
TDialogService.MessageDialog(
  'Save changes before closing?',
  TMsgDlgType.mtConfirmation,
  [TMsgDlgBtn.mbYes, TMsgDlgBtn.mbNo, TMsgDlgBtn.mbCancel],
  TMsgDlgBtn.mbYes,
  0,
  procedure(const R1: TModalResult)
  begin
    case R1 of
      mrYes:
        begin
          SaveDocument;
          TDialogService.MessageDialog(
            'Changes saved. Close now?',
            TMsgDlgType.mtInformation,
            [TMsgDlgBtn.mbOK, TMsgDlgBtn.mbCancel],
            TMsgDlgBtn.mbOK,
            0,
            procedure(const R2: TModalResult)
            begin
              if R2 = mrOk then
                CloseDocument;
            end);
        end;

      mrNo:
        TDialogService.MessageDialog(
          'Discard all changes?',
          TMsgDlgType.mtWarning,
          [TMsgDlgBtn.mbYes, TMsgDlgBtn.mbCancel],
          TMsgDlgBtn.mbCancel,
          0,
          procedure(const R2: TModalResult)
          begin
            if R2 = mrYes then
              CloseWithoutSaving;
          end);

      mrCancel:
        ;  // back to editor
    end;
  end);
```

Funcionalmente, essa é uma forma válida. O usuário vê uma pergunta, e a próxima
pergunta depende da primeira resposta.

O custo é a legibilidade. Cada decisão adicional pode acrescentar outro nível
de indentação. Esse não é um problema exclusivo de uma API de diálogo; é o preço
normal de fluxos assíncronos baseados em callback.

O Dialog4D não remove a forma assíncrona. Ele mantém o fluxo explícito, mas
tenta fazer cada chamada de diálogo carregar mais significado, reduzindo
cerimônia e permitindo legendas de botões específicas do domínio.

---

## Parte 8 — Botões como vocabulário

Botões padrão de diálogo são propositalmente pequenos e genéricos: `OK`,
`Cancel`, `Yes`, `No`, `Abort`, `Retry`, `Ignore` e assim por diante. Esse
vocabulário é perfeito para muitos diálogos.

Aplicações reais às vezes precisam de uma linguagem de ação mais específica.
Considere esta confirmação:

> **Apagar "Relatório Q4 2025.xlsx"? Este arquivo será removido permanentemente.**

As ações específicas do domínio são mais claras que Sim/Não genérico:

- "Apagar permanentemente"
- "Manter arquivo"

O Dialog4D adiciona `TDialog4DCustomButton` para esse caso. Cada botão
customizado carrega uma legenda, um `TModalResult` e flags de papel visual:

```delphi
TDialog4DCustomButton.Default     ('Salvar e fechar',     mrYes);
TDialog4DCustomButton.Destructive ('Apagar permanente',   mrYes);
TDialog4DCustomButton.Make        ('Fechar sem salvar',   mrNo);
TDialog4DCustomButton.Cancel      ('Manter arquivo');
```

Os construtores de conveniência representam quatro papéis:

- **Default** — a ação primária, renderizada com a cor de destaque e disparada
  pelo Enter no desktop.
- **Destructive** — uma ação perigosa, renderizada com a cor de erro.
- **Make** — uma ação neutra com flags explícitas.
- **Cancel** — uma ação de cancelamento, com `ModalResult = mrCancel`.

Botões customizados também podem usar resultados modais definidos pela
aplicação:

```delphi
const
  mrSalvarEFechar   = TModalResult(100);
  mrFecharSemSalvar = TModalResult(101);
```

```delphi
case AResult of
  mrSalvarEFechar:   SalvarEFechar;
  mrFecharSemSalvar: FecharSemSalvar;
  mrCancel:          VoltarAoEditor;
end;
```

`mrNone` é reservado como valor interno de "sem resultado" do Dialog4D e é
rejeitado como resultado de botão customizado.

Essa é a mudança conceitual:

> **O diálogo não é apenas uma pergunta Sim/Não.**  
> Ele pode ser uma lista de ações nomeadas, cada uma com seu próprio papel
> visual.

---

## Parte 9 — Capturando o estado certo: snapshots no momento da requisição

Um problema sutil aparece quando diálogos se tornam tematizáveis e
enfileiráveis.

Suponha que sua aplicação tenha um tema escuro e um tema claro. Ela enfileira um
diálogo enquanto o tema escuro está ativo, mas o usuário muda o tema antes que o
diálogo seja realmente exibido. Qual tema esse diálogo enfileirado deve usar?

O Dialog4D responde com snapshots no momento da requisição:

> **Quando `MessageDialogAsync` é chamado, o Dialog4D captura a configuração
> necessária para aquela requisição.**

Os dados capturados incluem:

- uma cópia por valor de `TDialog4DTheme`;
- a referência do text provider;
- o sink de telemetria;
- o callback de resultado;
- as definições dos botões, incluindo uma cópia do array de botões
  customizados.

Chamadas posteriores a `ConfigureTheme` não afetam requisições já em andamento.
Um diálogo enfileirado renderiza com o tema que estava ativo quando a requisição
foi feita.

Isso é intencionalmente um snapshot da configuração da requisição. Não é um
clone profundo de objetos arbitrários por trás das referências de provider ou
callback. O tema é copiado por valor, enquanto provider, sink e callback são
capturados como referências ou procedure values.

A seção 5.3 do demo distribuído (`Theme snapshot`) demonstra o comportamento
trocando temas entre diálogos.

---

## Parte 10 — Worker threads: esperar uma decisão sem bloquear a UI

A maioria dos fluxos de diálogo começa na main thread e continua por um
callback na main thread. Alguns fluxos são diferentes.

Considere uma operação de importação rodando em uma thread de trabalho:

```delphi
TTask.Run(
  procedure
  begin
    StartImport;
    ImportFirstBatch;

    if SomethingUnexpected then
    begin
      // Need to ask the user: continue or cancel?
      // But this code is running on a worker thread.
    end;

    ImportRemainingBatches;
  end);
```

A worker precisa de uma decisão antes de continuar. Uma chamada assíncrona normal
de diálogo retorna imediatamente, então a worker continuaria executando antes da
resposta ser conhecida.

O Dialog4D fornece `TDialog4DAwait.MessageDialogOnWorker` para essa forma
específica:

```delphi
TTask.Run(
  procedure
  var
    LStatus: TDialog4DAwaitStatus;
    LResult: TModalResult;
  begin
    StartImport;
    ImportFirstBatch;

    if SomethingUnexpected then
    begin
      LResult := TDialog4DAwait.MessageDialogOnWorker(
        'The import found unexpected data. Continue?',
        TMsgDlgType.mtConfirmation,
        [TMsgDlgBtn.mbYes, TMsgDlgBtn.mbNo],
        TMsgDlgBtn.mbYes,
        LStatus,
        'Import', nil, True,
        30_000  // 30-second timeout
      );

      if (LStatus = dasTimedOut) or (LResult = mrNo) then
        Exit;  // cancel the import
    end;

    ImportRemainingBatches;
  end);
```

Isso fornece à worker semântica de espera síncrona, preservando o pipeline
normal assíncrono da UI:

- a worker bloqueia aguardando resultado ou timeout;
- a main thread continua livre para renderizar e processar o diálogo;
- o diálogo visual é criado pelo pipeline normal do Dialog4D;
- o timeout encerra apenas a espera da worker, não o diálogo visual em si.

Há duas regras importantes:

> **`MessageDialogOnWorker` não pode ser chamado da main thread.**  
> O Dialog4D lança `EDialog4DAwait` imediatamente se você tentar.

O Dialog4D também lança `EDialog4DAwait` quando nenhum botão é fornecido ou
quando o pipeline interno não consegue apresentar o diálogo.

A razão é direta: a main thread é responsável por renderizar e processar o
diálogo. Se ela bloquear esperando o resultado do diálogo, o diálogo não poderá
ser concluído.

> **O timeout governa a paciência da worker, não o tempo de vida do diálogo.**  
> Quando o timeout expira, a worker retorna `dasTimedOut` com `mrNone`. O
> diálogo visual pode continuar na tela.

Se a aplicação quiser dispensar o diálogo ainda visível depois de um timeout,
ela pode solicitar `TDialog4D.CloseDialog` separadamente.

A sobrecarga smart `TDialog4DAwait.MessageDialog` detecta a thread chamadora:

- na main thread, delega para `MessageDialogAsync`;
- em uma worker thread, delega para `MessageDialogOnWorker`.

Quando chamada de uma worker thread, o callback executa na worker thread por
padrão. Passe `ACallbackOnMain = True` para reenviar esse callback para a main
thread.

A seção 8.1 do demo distribuído (`Worker await`) mostra esse padrão ao vivo,
com log do estado bloqueado da worker e do momento em que ela desbloqueia.

---

## Parte 11 — Fechamento programático, tema visual e telemetria

Mais três preocupações aparecem com frequência em aplicações em que diálogos
fazem parte do fluxo.

### Fechamento programático

Às vezes a aplicação precisa dispensar um diálogo sem esperar o usuário clicar
em um botão. Exemplos:

- a operação que motivou o diálogo é cancelada em outro ponto;
- uma resposta de servidor torna a pergunta obsoleta;
- uma worker thread atinge timeout e quer limpar o diálogo visível;
- a navegação leva o usuário para outra tela.

O Dialog4D adiciona `TDialog4D.CloseDialog` para esse caso:

```delphi
TDialog4D.CloseDialog(MyForm, mrCancel);
```

Isso solicita o fechamento do diálogo Dialog4D ativo para o formulário indicado.
O fechamento visual real é encaminhado para a main thread quando necessário. A
telemetria registra o fechamento como `crProgrammatic`.

### Tema visual como identidade da aplicação

Um diálogo não é apenas uma pergunta; ele também é uma superfície visual dentro
da aplicação. Se diálogos fazem parte da identidade visual da aplicação, pode
ser útil renderizá-los pelo mesmo modelo de estilo FMX do restante da UI.

`TDialog4DTheme` é um record por valor com campos para geometria, overlay,
tipografia, paleta de destaque, aparência dos botões e anel de destaque do
botão padrão:

```delphi
var
  LTheme: TDialog4DTheme;
begin
  LTheme := TDialog4DTheme.Default;
  LTheme.SurfaceColor     := $FF1E1E2E;
  LTheme.AccentInfoColor  := $FF89B4FA;
  LTheme.OverlayOpacity   := 0.60;
  TDialog4D.ConfigureTheme(LTheme);
end;
```

Temas são capturados no momento da requisição, então mudar o tema entre
requisições não afeta diálogos já enfileirados.

### Telemetria como observabilidade

Quando algo dá errado em produção, pode ser útil saber como o fluxo de diálogos
se comportou. O diálogo apareceu? Por quanto tempo ficou visível? Foi fechado
por botão, backdrop, tecla, fechamento programático ou destruição do formulário?

O Dialog4D emite eventos de ciclo de vida por meio de um sink de telemetria
configurável:

```delphi
TDialog4D.ConfigureTelemetry(
  procedure(const AData: TDialog4DTelemetry)
  begin
    TFile.AppendAllText(
      'dialog_events.log',
      TDialog4DTelemetryFormat.FormatTelemetry(AData) + sLineBreak);
  end);
```

Os eventos cobrem: `tkShowRequested`, `tkShowDisplayed`, `tkCloseRequested`,
`tkClosed`, `tkCallbackInvoked`, `tkCallbackSuppressed` e
`tkOwnerDestroying`.

A telemetria é best-effort. Exceções lançadas dentro do sink são engolidas pelo
pipeline do Dialog4D para que a instrumentação não quebre o fluxo do diálogo.

A telemetria registra o ciclo de vida do Dialog4D. Ela não deve ser tratada como
prova de que uma operação de domínio iniciada por um callback da aplicação
terminou com sucesso; sucesso ou falha de domínio pertencem à lógica da
aplicação.

---

## Parte 12 — Dialog4D: os conceitos em um pacote coeso

Juntando todas as peças, o Dialog4D consolida os padrões discutidos neste guia
em uma biblioteca de diálogos renderizada em FMX.

### O que cada peça resolve

| Conceito | O que resolve |
|---|---|
| `MessageDialogAsync` | Diálogos assíncronos com callback de resultado no caminho de UI da main thread |
| Fila FIFO por formulário | Requisições de diálogo para o mesmo formulário são serializadas automaticamente |
| Snapshot no momento da requisição | Valores de tema e configuração da requisição permanecem estáveis enquanto enfileirados |
| `TDialog4DCustomButton` | Botões com legendas em linguagem de domínio e papéis visuais |
| `TDialog4DAwait.MessageDialogOnWorker` | Worker threads podem esperar uma decisão do usuário sem bloquear a UI |
| `TDialog4D.CloseDialog` | Solicitação de fechamento programático do diálogo Dialog4D ativo |
| `TDialog4DTheme` | Tema visual configurável para diálogos renderizados em FMX |
| `IDialog4DTextProvider` | Text provider plugável para localização |
| `TDialog4D.ConfigureTelemetry` | Observabilidade de ciclo de vida com motivo de fechamento, contexto do botão e timing |
| `DialogService4D` | Adaptador para código callback no estilo do `FMX.DialogService` |

### Um exemplo completo amarrando as partes

Voltando ao cenário de fechamento de documento da Parte 1, escrito com
Dialog4D:

```delphi
uses
  Dialog4D,
  Dialog4D.Types;

procedure TForm1.btCloseClick(Sender: TObject);
begin
  TDialog4D.MessageDialogAsync(
    'You have unsaved changes.',
    TMsgDlgType.mtWarning,
    [
      TDialog4DCustomButton.Default     ('Save and Close',       mrYes),
      TDialog4DCustomButton.Destructive ('Close Without Saving', mrNo),
      TDialog4DCustomButton.Cancel      ('Review Changes')
    ],
    procedure(const R1: TModalResult)
    begin
      case R1 of
        mrYes:
          begin
            SaveDocument;
            TDialog4D.MessageDialogAsync(
              'Document saved. Close now?',
              TMsgDlgType.mtInformation,
              [
                TDialog4DCustomButton.Default ('Close Document', mrOk),
                TDialog4DCustomButton.Cancel  ('Keep Open')
              ],
              procedure(const R2: TModalResult)
              begin
                if R2 = mrOk then
                  CloseDocument;
              end,
              'Save Completed');
          end;

        mrNo:
          DiscardAndClose;

        mrCancel:
          ReturnToEditor;
      end;
    end,
    'Unsaved Changes');
end;
```

Esse código:

- usa uma única forma assíncrona de API Dialog4D nas plataformas FMX
  suportadas;
- mantém a main thread desbloqueada;
- fala linguagem de domínio nas legendas dos botões;
- torna a continuação explícita em callbacks;
- enfileira automaticamente se outra requisição Dialog4D já estiver ativa para
  o mesmo formulário;
- captura o tema ativo no momento da requisição;
- emite telemetria de ciclo de vida que a aplicação pode registrar para
  observabilidade.

### Uma nota sobre intenção

O Dialog4D foi criado para facilitar certas preocupações de diálogos FMX quando
elas aparecem juntas: fila, snapshots de requisição, botões customizados,
fechamento programático, tema visual, telemetria e semântica de espera em worker
thread.

Para uma mensagem simples com estilo de sistema/plataforma, `FMX.DialogService`
continua sendo uma boa escolha. Para aplicações em que diálogos fazem parte da
identidade visual e do fluxo da aplicação, o Dialog4D oferece esses padrões de
coordenação em um só lugar.

O resultado é uma superfície pública pequena — chamadas de configuração,
`MessageDialogAsync`, `CloseDialog` e a família await — com decisões explícitas
de ciclo de vida por baixo:

- fluxo assíncrono de diálogo na UI;
- fila FIFO por formulário;
- snapshots no momento da requisição;
- botões customizados com papéis visuais;
- await em worker thread com timeout;
- fechamento programático com encaminhamento para a main thread;
- tema visual configurável;
- text provider plugável;
- telemetria estruturada;
- segurança durante destruição de formulário com supressão de callback;
- e um adaptador para código callback comum no estilo do `FMX.DialogService`.

---

## Leituras recomendadas

Para leitores que querem se aprofundar em diálogos FMX e padrões assíncronos em
Delphi, estas referências são úteis:

- **[Embarcadero DocWiki — `TDialogService.MessageDialog`](https://docwiki.embarcadero.com/Libraries/Florence/en/FMX.DialogService.TDialogService.MessageDialog)** — referência oficial do serviço de diálogos FMX, incluindo comportamento síncrono/assíncrono conforme `PreferredMode` e plataforma.
- **[Embarcadero DocWiki — `TDialogService.TPreferredMode`](https://docwiki.embarcadero.com/Libraries/Florence/en/FMX.DialogService.TDialogService.TPreferredMode)** — descrição oficial dos modos `Platform`, `Async` e `Sync`.
- **[Embarcadero DocWiki — `FMX.Dialogs.MessageDlg`](https://docwiki.embarcadero.com/Libraries/Athens/en/FMX.Dialogs.MessageDlg)** — notas sobre `MessageDlg` legado, callbacks, comportamento bloqueante e suporte no Android.
- **[Marco Cantù — *Object Pascal Handbook*](https://www.embarcadero.com/products/delphi/object-pascal-handbook)** — livro/eBook sobre Object Pascal moderno, incluindo métodos anônimos.
- **[Guia conceitual do SafeThread4D](https://github.com/eduardoparaujo/SafeThread4D/blob/main/docs/Guide_pt-BR.md)** — para um tratamento mais profundo de threading, `Synchronize`, `Queue` e padrões de coordenação com worker threads mencionados ao longo deste guia.

---

## Epílogo — Próximos passos

Se você chegou até aqui, tem uma base conceitual sólida em diálogos FMX. Você
sabe por que cada camada da história dos diálogos existe, de uma simples
notificação até um mecanismo de diálogo com fila e observabilidade.

Próximos passos naturais:

1. **Clone o Dialog4D** e rode o demo distribuído. Cada uma das dez seções do
   demo corresponde a um conceito coberto neste guia.
2. **Leia o [README do projeto](../README.md)** para conhecer a superfície da
   API e exemplos de uso.
3. **Leia o [`Architecture.md`](Architecture.md)** se quiser entender o
   mecanismo por dentro — o registro, o host visual, o pipeline de fechamento, o
   tratamento de destruição de formulário e a camada await.
4. **Leia o código-fonte** com calma. A biblioteca não é grande, e as peças
   mapeiam diretamente para os conceitos deste guia.

Se você se encontrar repetidamente coordenando filas de diálogos, preservando
configuração visual entre requisições enfileiradas ou adicionando
observabilidade em torno de decisões por diálogo, o Dialog4D pode ser uma camada
útil para avaliar.

---

*Este texto é um guia conceitual introdutório. Para uso prático e detalhes do
mecanismo, consulte o [README.md](../README.md), as notas de arquitetura em
[`Architecture.md`](Architecture.md), e os exemplos do projeto.*
