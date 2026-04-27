# Do `ShowMessage` ao Dialog4D

### Uma jornada pelos diálogos do FMX, do problema real a um mecanismo para tratá-lo

---

Se você já escreveu algo em Delphi FMX que parecia síncrono, rodava bem no Windows e depois se comportou de forma diferente quando o mesmo código foi para iOS ou Android - diálogos que não bloqueavam, resultados que chegavam antes do esperado, trechos de código que executavam antes do usuário responder - este texto é para você.

O Delphi já fornece os mecanismos de diálogo com os quais a maioria das aplicações FMX deveria começar: `ShowMessage`, `MessageDlg` e, especialmente, `FMX.DialogService`. Essas APIs são práticas, oficialmente suportadas e totalmente apropriadas para muitos cenários.

Este guia segue um caminho natural: começar pelo diálogo mais simples do FMX (`ShowMessage`), observar como cada camada se comporta conforme os requisitos da aplicação crescem, e só então introduzir os conceitos que ajudam a tratar essas necessidades quando as ferramentas básicas já não são suficientes.

Ao final, o objetivo é que você entenda não apenas **como** usar diálogos no Delphi FMX, mas **por que** cada camada da história dos diálogos existe. Como culminação prática, você verá o **Dialog4D**, um mecanismo complementar que consolida essas decisões em uma API pequena na superfície, mas projetada para tornar as decisões do usuário explícitas, previsíveis e visualmente consistentes em desktop e mobile.

> **Uma nota sobre posicionamento.** O Dialog4D não substitui os mecanismos de diálogo que acompanham o Delphi. `ShowMessage`, `MessageDlg` e `FMX.DialogService` continuam sendo escolhas válidas em muitos cenários e são o ponto de partida natural para aplicações FMX. O Dialog4D é uma camada complementar para aplicações em que os diálogos passam a fazer parte da identidade visual e do fluxo da aplicação. A intenção deste guia não é argumentar que os mecanismos padrão estão errados, mas percorrer o espaço de design dos diálogos no FMX e mostrar onde um mecanismo dedicado passa a ser útil.

> **Nota sobre pré-requisitos.** Este guia foca em diálogos no FMX. Ele assume que você está confortável com métodos anônimos (closures), `TThread.Queue` para enviar trabalho à thread principal e vocabulário básico de threading. Se esses conceitos forem novos para você, o [guia conceitual do SafeThread4D](https://github.com/eduardoparaujo/SafeThread4D/blob/main/docs/Guide_pt-BR.md) cobre tudo isso em detalhe e é o companheiro natural deste texto.

---

## Parte 1 - Por que diálogos precisam de um ciclo de vida explícito

Um diálogo parece uma coisinha pequena e inofensiva. O usuário clica em um botão, uma janela aparece perguntando "Salvar alterações?", o usuário escolhe uma resposta e a aplicação continua. Três linhas de código, nada demais.

O problema é que "a aplicação continua" não é um único conceito. São pelo menos três coisas diferentes:

1. **A aplicação continua desenhando a interface.** Animações continuam rodando, timers continuam disparando, eventos continuam chegando.
2. **A aplicação continua o método que chamou o diálogo.** A linha logo após a chamada executa em algum momento.
3. **A aplicação continua o fluxo do usuário.** A próxima decisão, a próxima tela, a próxima pergunta dependem da resposta.

Em uma aplicação desktop rodando no Windows, as três coisas às vezes parecem a mesma coisa: o diálogo bloqueia tudo, o usuário responde e a execução retoma a partir da linha logo após a chamada. A ilusão de que "a aplicação parou e depois continuou" funciona.

Essa ilusão não sobrevive ao FMX em mobile. No iOS e no Android, o sistema operacional não permite que a aplicação bloqueie a thread principal esperando uma decisão do usuário. A interface precisa continuar renderizando, animando e respondendo a eventos do sistema enquanto o diálogo está visível. A plataforma força uma forma diferente: **a chamada que mostra um diálogo retorna imediatamente, e a resposta chega depois através de um callback.**

Isso não é uma peculiaridade do FMX. É o modelo de plataforma de qualquer sistema operacional móvel moderno. Uma vez que você aceita esse fato, todas as outras peças do design de diálogos passam a fazer sentido.

---

## Parte 2 - `ShowMessage`: o diálogo mais simples, e sua primeira divergência

O diálogo FMX mais básico é o `ShowMessage`, da unit `FMX.Dialogs`:

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

Você lê esse código de cima para baixo e espera: salvar o documento, mostrar uma confirmação, fechar o documento.

No Windows, é exatamente isso que acontece. O diálogo aparece, a aplicação espera o usuário fechá-lo e então `CloseDocument` executa.

No iOS e no Android, **não é** isso que acontece. `ShowMessage` retorna imediatamente. O diálogo aparece na tela, mas `CloseDocument` executa **antes** do usuário dispensá-lo. Quando o usuário toca em "OK", o documento já foi fechado.

A razão é exatamente a discutida na Parte 1: a plataforma móvel não permite que a thread principal bloqueie esperando entrada do usuário. `ShowMessage` é um wrapper fino que, no mobile, retorna imediatamente para manter a interface responsiva. O diálogo visível é apenas um efeito colateral - a chamada com aparência síncrona é uma ilusão.

Essa é a primeira divergência importante de comportamento entre plataformas em diálogos FMX:

> **`ShowMessage` parece síncrono, mas só é síncrono no Windows.**  
> **No mobile, a linha após a chamada executa antes do usuário responder.**

Se o seu código só roda no Windows, dá para usar `ShowMessage` para notificações simples e a suposição se mantém. Assim que o mesmo código for compilado para iOS ou Android, a suposição quebra silenciosamente. O bug é difícil de encontrar porque o código parece correto.

Um modelo mental mais seguro é assumir desde o início que **um diálogo nunca é uma interrupção síncrona** - ele é uma notificação que roda em paralelo com o resto do código. Com essa suposição, você não escreveria `CloseDocument` depois de `ShowMessage`. Você ou executaria `CloseDocument` antes e notificaria depois, ou usaria uma API de diálogo que ofereça um callback para "depois que o usuário respondeu".

---

## Parte 3 - `MessageDlg`: a mesma armadilha entre plataformas, com mais botões

`MessageDlg` é o próximo passo. Também está em `FMX.Dialogs`, e permite mostrar um diálogo com vários botões e fazer uma pergunta ao usuário:

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

Esse padrão está em todo lugar no código Delphi legado. Lê como um `if` normal: "se o usuário disse sim, salva; depois fecha". O retorno de `MessageDlg` é o resultado modal, e o código se ramifica com base nele.

No Windows, isso funciona como se lê. No iOS, a sobrecarga legada bloqueante ainda pode se comportar de forma síncrona. No Android, porém, essa forma bloqueante não é suportada. Quando se usa uma sobrecarga baseada em callback, a continuação deixa de ser o valor de retorno: no mobile, código colocado depois da chamada pode executar antes que a decisão do usuário seja entregue.

A lição importante não é que toda sobrecarga de `MessageDlg` sempre retorna imediatamente. A lição é que `MessageDlg` tem comportamento dependente de plataforma e de sobrecarga, o que torna o fluxo baseado em valor de retorno uma base frágil para código FMX que precisa se comportar de forma consistente entre Windows, macOS, iOS e Android.

No FMX, o valor de retorno de `MessageDlg` não deve ser tratado como o principal ponto de decisão entre plataformas. A função legada continua familiar para desenvolvedores Delphi, mas quando a resposta realmente importa em desktop e mobile, um formato baseado em callback é mais seguro e mais fácil de raciocinar.

É exatamente isso que o `FMX.DialogService` oferece.

---

## Parte 4 - `FMX.DialogService`: o caminho recomendado

`FMX.DialogService` é o serviço oficial de diálogos do FMX, e é a família de APIs para a qual a Embarcadero direciona o desenvolvedor ao migrar chamadas legadas de diálogo de `FMX.Dialogs`. Ele expõe a mesma família de chamadas `MessageDialog`, mas a resposta é entregue através de um callback anônimo em vez de ser tratada como um ponto de decisão por valor de retorno dependente da plataforma:

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

A forma é diferente. A decisão deixou de ser um valor de retorno testado em um `if` - agora é um parâmetro entregue a um callback que executa **depois** que o usuário respondeu. A chamada para `CloseDocument` se moveu para dentro do callback, onde ela pertence: depois que a resposta é conhecida.

Isso é uma melhoria real. A continuação fica explícita: o código que depende da resposta do usuário vive dentro do callback de fechamento. Dependendo do `PreferredMode`, a chamada em si pode ser síncrona no desktop ou assíncrona no mobile, mas o ponto de decisão é consistente: o callback é invocado depois que o usuário fecha o diálogo. Para a maioria dos casos simples, `FMX.DialogService` é a escolha correta e não há razão para procurar outra coisa. O resto deste guia **não** é um argumento de que `FMX.DialogService` deva ser evitado - é uma exploração do espaço de design dos diálogos no FMX, mostrando onde preocupações adicionais aparecem e como podem ser tratadas quando aparecem.

### `PreferredMode`: uma ponte parcial entre expectativas de desktop e mobile

`FMX.DialogService` oferece uma configuração chamada `PreferredMode`, que controla como os diálogos são apresentados:

```delphi
TDialogService.PreferredMode := TDialogService.TPreferredMode.Sync;
```

Os valores são `Sync`, `Async` e `Platform`.

Na prática, `Platform` se comporta de forma diferente dependendo da família de plataformas: desktop prefere comportamento síncrono, enquanto mobile usa comportamento assíncrono. Além disso, `Sync` não é suportado no Android. Isso significa que código desktop ainda pode ser escrito em um estilo mais síncrono, enquanto código mobile ainda precisa ser tratado como assíncrono.

Por essa razão, se o mesmo código FMX precisa se comportar de forma consistente entre desktop e mobile, é mais seguro adotar um modelo mental assíncrono desde o início.

É essa percepção que motiva o restante deste guia: **uma vez que você se compromete com a forma assíncrona, novas perguntas de design aparecem**.

---

## Parte 5 - Diálogo como roteador de fluxo

Uma vez que você aceita que as chamadas de diálogo são assíncronas, passa a vê-las de forma diferente. Elas não são "perguntas que você faz"; são **ramificações no fluxo da sua aplicação**.

Veja este código:

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

O método `PrepareToCloseDocument` faz duas coisas visualmente: valida o estado e depois faz uma pergunta. Mas o comportamento entre plataformas deve ser entendido de outra forma. As linhas que decidem o que vai acontecer em seguida - `SaveAndClose`, `CloseWithoutSaving`, ou nada - vivem dentro do callback. No mobile, o método pode retornar antes de o usuário responder; no desktop, dependendo do modo preferido, ele pode esperar. O ponto essencial é que a continuação pertence ao callback, porque o callback é o local comum onde a resposta é conhecida de forma consistente.

Esse é um modelo mental útil:

> **Uma chamada de diálogo perto do final de um método age como um roteador de fluxo.**  
> O método original termina; o resto do fluxo da aplicação continua através de uma das ramificações do callback.

Isso funciona bem, mas só sob uma condição: a chamada do diálogo precisa ser tratada como **a última coisa significativa que o método faz**. Se você escrever código depois da chamada do diálogo, esse código não é um ponto de continuação confiável entre plataformas; no mobile ou em modo assíncrono, ele pode executar antes de o usuário responder.

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

  CloseDocument;  // <- BUG no mobile/modo assíncrono: pode executar antes de o usuário responder.
end;
```

É o mesmo problema de comportamento entre plataformas das Partes 2 e 3, mas expresso de forma mais sutil. Mesmo quando a API do diálogo oferece o callback correto, o desenvolvedor ainda pode escrever código com aparência síncrona ao redor dela e produzir um bug entre plataformas.

Disso emerge uma disciplina:

> **No FMX, trate toda chamada de diálogo como o fim do método.**  
> **O que precisar rodar depois da decisão do usuário pertence ao callback.**

Se você internalizar essa regra, passa a escrever métodos onde a chamada do diálogo é naturalmente a última instrução, e o callback contém a continuação. Essa é a forma que escala - a próxima parte mostra por quê.

---

## Parte 6 - Quando o roteador encontra concorrência: o problema da fila

O padrão "diálogo como roteador de fluxo" funciona perfeitamente quando **você** é o único roteando. O método que abre o diálogo é também o método que decide o que vem a seguir. Há uma única origem de requisições de diálogo, e ela é a chamada que você acabou de fazer.

Aplicações reais raramente são tão simples.

Imagine uma tela com três fontes independentes de requisições de diálogo:

- um botão que o usuário clica para confirmar uma ação;
- um timer que dispara a cada minuto e avisa sobre expiração de sessão;
- um handler de resposta HTTP que mostra um erro do servidor quando uma chamada de API falha.

Cada uma dessas fontes pode requisitar um diálogo **a qualquer momento**. O usuário pode clicar no botão de confirmação enquanto o aviso de expiração de sessão está prestes a disparar, enquanto um erro de servidor está chegando em segundo plano. Nenhuma das três fontes sabe das outras duas.

Com `FMX.DialogService`, o que acontece?

```delphi
// Fonte 1: clique de botão
TDialogService.MessageDialog(
  'Confirm purchase?',
  TMsgDlgType.mtConfirmation,
  [TMsgDlgBtn.mbYes, TMsgDlgBtn.mbNo],
  TMsgDlgBtn.mbYes,
  0,
  procedure(const R: TModalResult) begin ... end);

// Fonte 2: timer (executa ao mesmo tempo)
TDialogService.MessageDialog(
  'Your session expires in 2 minutes.',
  TMsgDlgType.mtWarning,
  [TMsgDlgBtn.mbOK],
  TMsgDlgBtn.mbOK,
  0,
  procedure(const R: TModalResult) begin ... end);

// Fonte 3: erro de servidor (também executa ao mesmo tempo)
TDialogService.MessageDialog(
  'Network request failed.',
  TMsgDlgType.mtError,
  [TMsgDlgBtn.mbRetry, TMsgDlgBtn.mbCancel],
  TMsgDlgBtn.mbRetry,
  0,
  procedure(const R: TModalResult) begin ... end);
```

Três requisições independentes de diálogo podem chegar quase ao mesmo tempo. `FMX.DialogService` não expõe um mecanismo documentado de serialização FIFO por formulário, então a aplicação precisa coordenar requisições sobrepostas se quiser que elas se comportem de forma sequencial e previsível.

A correção ingênua é garantir que a aplicação nunca peça dois diálogos concorrentemente. Mas isso é uma disciplina, não uma garantia. Para impor isso, o desenvolvedor teria que:

- rastrear quais diálogos estão visíveis em cada momento;
- enfileirar manualmente novas requisições quando um diálogo já estiver aberto;
- despachar as requisições enfileiradas quando o diálogo ativo fechar;
- lidar com condições de corrida entre o callback de fechamento e novos pedidos chegando.

Em outras palavras: o desenvolvedor teria que reimplementar uma fila, à mão, toda vez. E acertar toda vez. E lembrar de conectar isso em todas as fontes de requisições de diálogo na aplicação.

Esse é exatamente o tipo de preocupação estrutural que não pertence ao código da aplicação:

> **Com `FMX.DialogService`, fluxo sequencial de diálogos é uma convenção.**  
> **O código da aplicação precisa coordenar explicitamente requisições sobrepostas.**

O Dialog4D aborda isso de forma diferente. O framework tem uma fila FIFO por formulário embutida no mecanismo. Toda requisição de diálogo para o mesmo formulário é automaticamente serializada: a segunda requisição espera na fila até a primeira fechar, a terceira espera a segunda, e assim por diante. O desenvolvedor não coordena nada - o framework coordena.

> **Com Dialog4D, fluxo sequencial de diálogos é uma garantia do mecanismo.**

Esse é um tipo diferente de correção. O código da aplicação não precisa ser defensivo a respeito de requisições concorrentes de diálogo. A fila é uma propriedade do sistema, não uma disciplina do programador.

A seção 5.1 do demo distribuído com o repositório (`Queue Demo`) mostra isso diretamente: dispara seis diálogos em um loop apertado a partir de um worker `TTask.Run`, e o framework os enfileira automaticamente. O usuário vê um diálogo de cada vez, na ordem de chegada, sem sobreposição e sem perda.

---

## Parte 7 - Decisões sequenciais e a profundidade de callbacks aninhados

Mesmo dentro de uma única fonte de requisições de diálogo, decisões em múltiplas etapas trazem seu próprio desafio de design.

Imagine um diálogo "Salvar antes de fechar?" onde cada resposta leva a uma pergunta seguinte:

- "Sim" -> salva e depois pergunta "Fechar agora?"
- "Não" -> pergunta "Tem certeza? Descartar não pode ser desfeito."
- "Cancelar" -> volta ao editor, sem pergunta seguinte.

Escrito com `FMX.DialogService`, fica assim:

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

Funcionalmente, isso funciona. O usuário vê um diálogo de cada vez, as respostas são processadas corretamente, e o fluxo termina no lugar certo.

Visualmente, a indentação cresce. Cada ramo que adiciona um diálogo seguinte adiciona um nível de aninhamento. Uma decisão de três etapas já está empurrando a margem direita do editor. Uma decisão de quatro etapas fica difícil de ler, e mudanças em um ramo exigem navegação cuidadosa para garantir que você está editando a closure certa.

É uma forma bem conhecida - é o mesmo "callback hell" que o JavaScript enfrentou antes de promises e async/await. No Delphi FMX não existe async/await embutido para diálogos, então a indentação é o preço da correção.

O Dialog4D não elimina o aninhamento - não pode, porque a forma assíncrona é fundamental. Mas torna o código aninhado mais curto e mais claro de duas maneiras:

**1. Menos cerimônia por chamada.** O parâmetro `0` para `HelpCtx` desaparece, os prefixos de tipo ficam mais curtos, o parâmetro de botão padrão se integra ao modelo de snapshot.

**2. Botões customizados substituem semântica genérica de Yes/No.** Em vez de `mbYes`/`mbNo` e um comentário explicando o que cada um significa, os botões carregam suas próprias legendas e papéis:

```delphi
TDialog4D.MessageDialogAsync(
  'You have unsaved changes.',
  TMsgDlgType.mtWarning,
  [
    TDialog4DCustomButton.Default('Save and Close', mrYes),
    TDialog4DCustomButton.Destructive('Close Without Saving', mrNo),
    TDialog4DCustomButton.Cancel('Review Changes')
  ],
  procedure(const R1: TModalResult)
  begin
    case R1 of
      mrYes:    SaveAndClose;
      mrNo:     CloseWithoutSaving;
      mrCancel: ReturnToEditor;
    end;
  end,
  'Unsaved Changes');
```

O diálogo agora fala em linguagem do domínio. Um revisor lendo o código vê "Save and Close", "Close Without Saving", "Review Changes" - três ações com significado claro. A próxima parte é dedicada a esse conceito.

---

## Parte 8 - Botões como vocabulário

Em uma API clássica de diálogo, os botões são um enum: `mbOK`, `mbCancel`, `mbYes`, `mbNo`, `mbAbort`, `mbRetry`, `mbIgnore`, `mbAll`, `mbNoToAll`, `mbYesToAll`, `mbHelp`, `mbClose`. O texto de cada botão vem de um text provider - por padrão, as legendas em inglês "OK", "Cancel", "Yes", "No", e assim por diante.

Isso funciona para diálogos de confirmação simples. "Tem certeza que quer apagar?" -> Sim / Não. A semântica é universal o suficiente para que "Sim" e "Não" signifiquem a mesma coisa em qualquer contexto.

Aplicações reais frequentemente precisam de linguagem mais específica. Veja esta confirmação:

> **Apagar "Relatório Q4 2025.xlsx"? Este arquivo será removido permanentemente.**

O que os botões deveriam dizer? As opções padrão são pouco satisfatórias:

- "Sim" / "Não" - vago demais. O que significa "Sim"? Sim, apagar? Sim, manter?
- "OK" / "Cancelar" - também vago. Cancelar o quê?
- "Abortar" / "Tentar de novo" / "Ignorar" - vocabulário totalmente errado.

Os botões que correspondem à pergunta são:

- "Apagar permanentemente"
- "Manter arquivo"

Essas legendas não estão em nenhum enum padrão. São específicas do domínio. São mais claras que qualquer combinação das opções padrão, porque são escritas na linguagem da ação.

`FMX.DialogService` não oferece suporte de primeira classe para legendas customizadas por chamada. O Dialog4D introduz `TDialog4DCustomButton`, um record que carrega uma legenda, um `TModalResult` e duas flags visuais:

```delphi
TDialog4DCustomButton.Default     ('Salvar e fechar',     mrYes);
TDialog4DCustomButton.Destructive ('Apagar permanente',   mrYes);
TDialog4DCustomButton.Make        ('Fechar sem salvar',   mrNo);
TDialog4DCustomButton.Cancel      ('Manter arquivo');
```

Quatro construtores de conveniência mapeiam para quatro papéis visuais:

- **Default** - a ação primária, renderizada com a cor de destaque e disparada pelo Enter no desktop.
- **Destructive** - uma ação perigosa, renderizada com a cor de erro (tipicamente vermelho).
- **Make** - uma ação neutra com flags explícitas.
- **Cancel** - uma ação tipo cancelar, com `ModalResult` sempre `mrCancel`.

As legendas são passadas como strings, sem enum no meio. A aplicação escolhe o que os botões dizem na linguagem do domínio. O `TModalResult` é um inteiro que o callback usa para identificar a resposta.

Há também um efeito colateral útil: os botões podem carregar resultados modais **definidos pela aplicação**, não apenas os padrão:

```delphi
const
  mrSalvarEFechar = TModalResult(100);
  mrFecharSemSalvar = TModalResult(101);
```

E o callback pode fazer switch sobre o vocabulário próprio da aplicação:

```delphi
case AResult of
  mrSalvarEFechar:   SalvarEFechar;
  mrFecharSemSalvar: FecharSemSalvar;
  mrCancel:          VoltarAoEditor;
end;
```

É uma pequena mudança de forma com uma consequência significativa:

> **O diálogo não é mais uma pergunta genérica de Sim/Não.**  
> **É uma lista de ações nomeadas, cada uma com seu próprio papel visual.**

A seção 10.3 do demo distribuído (`Custom buttons - all four visual roles`) mostra esse padrão com os quatro construtores visíveis ao mesmo tempo.

---

## Parte 9 - Capturando o estado certo: snapshot no momento da chamada

Um problema sutil aparece quando você passa a usar temas e customização no nível do diálogo.

Suponha que sua aplicação tenha dois temas: um tema claro para uso diurno e um tema escuro para uso noturno. O usuário pode alternar entre eles a qualquer momento. A aplicação tem o seguinte código:

```delphi
ApplyDarkTheme;

// Step 1: ask the user to confirm
TDialog4D.MessageDialogAsync(
  'Save before closing?',
  ...,
  procedure(const R1: TModalResult)
  begin
    if R1 = mrYes then
    begin
      ApplyLightTheme;  // theme switch between dialogs

      // Step 2: confirm save success
      TDialog4D.MessageDialogAsync(
        'Saved successfully.',
        ...,
        procedure(const R2: TModalResult)
        begin
          ...
        end);
    end;
  end);
```

O primeiro diálogo deveria renderizar no tema escuro. O segundo, no tema claro. O comportamento visível para o usuário deveria casar com o tema que estava ativo no momento em que cada diálogo foi requisitado.

Mas o que acontece se houver pressão de fila? E se outro diálogo de outra fonte já estiver na tela, e o Passo 1 entrar na fila e esperar? Quando o Passo 1 finalmente renderizar, qual tema deveria usar - o tema que estava ativo no momento do pedido, ou o tema global atual?

Não é uma situação hipotética. Acontece sempre que a aplicação:

- muda o tema em resposta a preferências do usuário;
- muda o tema com base na hora do dia;
- muda o text provider para localização;
- muda o sink de telemetria para testes.

Se o diálogo usar o estado global **atual** no momento da renderização, ele pode usar um tema que o desenvolvedor nunca pretendeu para aquele diálogo específico. O usuário vê o Passo 1 renderizado no tema claro mesmo o tema escuro estando ativo no momento da pergunta. O fluxo visual fica incoerente.

O Dialog4D resolve isso com **snapshot no momento da chamada**:

> **Quando `MessageDialogAsync` é chamado, o framework captura uma cópia do `FTheme` atual e uma referência ao `FTextProvider` atual dentro da requisição.**  
> **O diálogo renderiza com a configuração que estava ativa no momento da chamada, independentemente do que aconteça com o estado global depois.**

O snapshot é uma cópia por valor. Chamadas subsequentes a `ConfigureTheme` não afetam requisições já em andamento. Um fluxo de decisão em múltiplas etapas que troca o tema entre passos vai renderizar cada passo com o tema que estava ativo quando aquele passo foi requisitado.

É isso que torna o Dialog4D seguro para aplicações que mudam configuração global em tempo de execução. O desenvolvedor não precisa se preocupar com timing - o framework garante a identidade visual que cada requisição deveria ter.

A seção 5.3 do demo distribuído (`Theme snapshot during queue`) demonstra isso diretamente: mostra um diálogo no tema padrão, troca para o tema cyberpunk entre diálogos, e o segundo diálogo renderiza corretamente com o novo tema sem afetar o primeiro.

---

## Parte 10 - Worker threads: esperar uma decisão sem bloquear a UI

Até aqui, o modelo do diálogo foi: a thread principal faz uma pergunta, o usuário responde, o callback executa na thread principal. Isso cobre a maioria dos casos.

Alguns casos são diferentes. Imagine uma operação de importação rodando numa worker thread:

```delphi
TTask.Run(
  procedure
  begin
    StartImport;
    ImportFirstBatch;

    if SomethingUnexpected then
    begin
      // Need to ask the user: continue or cancel?
      // But we are on a worker thread.
    end;

    ImportRemainingBatches;
  end);
```

A worker thread precisa fazer uma pergunta ao usuário e esperar a resposta antes de decidir o que fazer em seguida. A decisão afeta o fluxo da worker, não o fluxo da UI.

A abordagem ingênua - chamar `TDialog4D.MessageDialogAsync` da worker - não funciona, porque `MessageDialogAsync` retorna imediatamente. A worker continuaria executando sem esperar a resposta do usuário. O callback chegaria depois, na thread principal, sem forma de retornar para a lógica da worker.

A forma correta é: a worker **bloqueia** até o usuário responder. A thread principal renderiza o diálogo normalmente e continua responsiva. Quando o usuário responde, a worker desbloqueia com o resultado.

O Dialog4D fornece `TDialog4DAwait.MessageDialogOnWorker` exatamente para isso:

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

A worker bloqueia na chamada de await. A thread principal continua renderizando normalmente. O diálogo aparece, o usuário responde, e a worker desbloqueia com o resultado.

Há uma regra importante:

> **`MessageDialogOnWorker` não pode ser chamada da thread principal.**  
> **O framework lança `EDialog4DAwait` imediatamente se você tentar.**

A razão é simples: a thread principal é a que deveria renderizar o diálogo. Se a thread principal estiver parada esperando o diálogo fechar, ninguém poderá renderizá-lo, e a aplicação entra em deadlock. A biblioteca se recusa a entrar nesse estado.

Uma segunda regra sobre o timeout:

> **O timeout governa a paciência da worker, não o tempo de vida do diálogo.**  
> **Quando o timeout expira, a worker para de esperar e retorna `dasTimedOut`. O diálogo continua na tela até o usuário dispensá-lo manualmente.**

Se você quiser fechar o diálogo depois de um timeout da worker, pode chamar `TDialog4D.CloseDialog` da própria worker - a próxima parte cobre isso.

A sobrecarga "smart" de `MessageDialog` (sem o `OnWorker`) detecta a thread chamadora e adapta: na thread principal delega para `MessageDialogAsync` (não bloqueante), na worker delega para `MessageDialogOnWorker` (bloqueante). Isso permite que código compartilhado chame `MessageDialog` independentemente do contexto de thread, mas vale mais quando a thread chamadora é genuinamente incerta - quando você sabe em qual thread está, as chamadas explícitas são mais claras.

A seção 8.1 do demo distribuído (`MessageDialogOnWorker - blocking`) mostra esse padrão ao vivo, com log do estado bloqueado da worker e do momento em que ela desbloqueia.

---

## Parte 11 - Fechamento programático, tema visual e telemetria

Mais três preocupações aparecem em aplicações reais, e o Dialog4D trata cada uma.

### Fechar o diálogo ativo de forma programática

Às vezes a aplicação precisa fechar um diálogo sem o usuário clicar em um botão. Exemplos:

- a operação que motivou o diálogo é cancelada por outra parte da aplicação;
- uma resposta de servidor torna a pergunta obsoleta;
- uma worker thread atinge timeout e quer limpar o diálogo visível;
- o fluxo de navegação se move para outra tela.

`FMX.DialogService` não oferece uma forma embutida de fechar programaticamente o diálogo ativo. O diálogo continua visível até o usuário fechá-lo, mesmo que a pergunta não seja mais relevante.

O Dialog4D oferece `TDialog4D.CloseDialog`:

```delphi
// Thread-safe - pode ser chamado de qualquer thread
TDialog4D.CloseDialog(MyForm, mrCancel);
```

O diálogo ativo do formulário é descartado, o callback do usuário dispara com o resultado que você passou, e a fila avança normalmente. A telemetria registra o fechamento como `crProgrammatic`.

É isso que permite padrões de limpeza como "o diálogo pede confirmação, mas se o usuário demorar demais, cancelamos automaticamente e seguimos com uma ação padrão".

### Tema visual como identidade da aplicação

Um diálogo não é apenas uma pergunta - é uma superfície visual que participa da identidade da aplicação. Diálogos padrão do SO têm uma aparência. Diálogos temáticos na paleta da sua aplicação têm outra. O mesmo diálogo mostrado em um tema corporativo neutro lê diferente do mesmo diálogo mostrado em um tema neon de alto contraste.

O Dialog4D trata o tema visual como uma preocupação de primeira classe. `TDialog4DTheme` é um record copiado por valor com campos para geometria, overlay, tipografia, paleta de destaque, visuais de botão e o anel de destaque do botão padrão. O tema é configurado globalmente:

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

Temas são capturados como snapshots no momento da chamada (Parte 9), então mudar o tema entre diálogos não afeta diálogos já em andamento.

As seções 2.1, 2.2 e 2.3 do demo distribuído mostram três temas pré-construídos - *Custom*, *Dark* e *Cyberpunk* - com o mesmo diálogo renderizado em três identidades visuais completamente diferentes.

### Telemetria como observabilidade

Quando algo dá errado em produção, você quer saber o que o usuário fez. Ele clicou no botão perigoso? Cancelou? Ignorou o aviso? O diálogo chegou a aparecer?

`FMX.DialogService` não oferece telemetria estruturada embutida para ciclo de vida de diálogo e motivos de fechamento. O diálogo aparece, o callback dispara, o resultado é entregue - mas não há um registro pronto do fluxo completo da interação.

O Dialog4D emite sete eventos de ciclo de vida através de um sink de telemetria configurável:

```delphi
TDialog4D.ConfigureTelemetry(
  procedure(const AData: TDialog4DTelemetry)
  begin
    TFile.AppendAllText(
      'dialog_events.log',
      TDialog4DTelemetryFormat.FormatTelemetry(AData) + sLineBreak);
  end);
```

Os eventos cobrem o ciclo de vida completo: `tkShowRequested`, `tkShowDisplayed`, `tkCloseRequested`, `tkClosed`, `tkCallbackInvoked`, `tkCallbackSuppressed`, `tkOwnerDestroying`. Cada evento carrega o tipo de diálogo, título, comprimento da mensagem, quantidade de botões, resultado padrão, motivo do fechamento (botão, overlay, tecla, programático, formulário sendo destruído), o botão disparado (tipo e legenda), tempo decorrido e timestamp absoluto.

O sink é best-effort: exceções lançadas dentro do sink são silenciosamente engolidas pelo framework. Um consumidor de telemetria com defeito não pode quebrar o fluxo do diálogo.

É isso que transforma a interação com diálogo em **comportamento observável da aplicação**. A seção 2.6 do demo distribuído alterna telemetria ao vivo e mostra cada evento fluindo para o log na tela.

---

## Parte 12 - Dialog4D: os conceitos em um pacote coeso

Juntando todas as peças, o Dialog4D é o mecanismo de diálogos FMX que consolida as decisões apresentadas ao longo deste guia.

### O que cada peça resolve

| Conceito | O que resolve |
|---|---|
| `MessageDialogAsync` | Diálogos assíncronos com callback que executa na thread principal, em todas as plataformas |
| Fila FIFO por formulário | Requisições concorrentes são serializadas automaticamente; sem sobreposição |
| Snapshot no momento da chamada | Tema e text provider capturados no momento da chamada; não afetados por mudanças posteriores |
| `TDialog4DCustomButton` | Botões com legendas em linguagem do domínio e quatro papéis visuais (default, destructive, cancel, neutral) |
| `TDialog4DAwait.MessageDialogOnWorker` | Worker threads podem esperar uma decisão do usuário sem bloquear a UI |
| `TDialog4D.CloseDialog` | Descarte programático do diálogo ativo, de qualquer thread |
| `TDialog4DTheme` | Tema visual de primeira classe com modelo de snapshot |
| `IDialog4DTextProvider` | Text provider plugável para localização |
| `TDialog4D.ConfigureTelemetry` | Sete eventos de ciclo de vida com motivo de fechamento, contexto do botão e timing |
| `DialogService4D` | facade de migração drop-in para chamadores do `FMX.DialogService` |

### Um exemplo completo amarrando as partes

Voltando ao cenário de fechamento de documento da Parte 1, escrito com Dialog4D:

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

- funciona de forma idêntica em Windows, macOS, iOS e Android;
- nunca bloqueia a thread principal, em nenhuma plataforma;
- fala linguagem do domínio nas legendas dos botões;
- reforça o padrão "diálogo como roteador de fluxo" pela própria forma;
- enfileira automaticamente se outro diálogo for requisitado concorrentemente para o mesmo formulário;
- captura o tema ativo no momento da chamada, imune a mudanças de tema entre passos;
- emite eventos de telemetria que um sink externo pode registrar para observabilidade.

Essas propriedades não são recursos opt-in. São o comportamento padrão de toda chamada `MessageDialogAsync`.

### Uma nota sobre intenção

O Dialog4D não foi construído para competir com `FMX.DialogService`. Foi construído para tratar os casos em que a abordagem recomendada começa a empurrar preocupações de coordenação para dentro do código da aplicação: fila, snapshots, botões customizados, fechamento programático, consistência de tema visual, telemetria e integração com worker threads. Para o caso simples de uma mensagem pontual com estilo do sistema operacional, `FMX.DialogService` continua sendo uma boa escolha. Para aplicações em que os diálogos fazem parte da identidade visual e do fluxo da aplicação, o Dialog4D consolida os padrões em um mecanismo que não precisa ser reconstruído em cada projeto.

O resultado é uma API com superfície pública pequena - três chamadas de configuração, duas sobrecargas de `MessageDialogAsync`, um `CloseDialog`, e a família await - mas densa em decisões corretas por baixo. Com uma pequena quantidade de configuração, o desenvolvedor obtém:

- diálogos assíncronos com ciclo de vida determinístico em todas as plataformas;
- fila FIFO por formulário sem coordenação manual;
- isolamento de requisições enfileiradas baseado em snapshot;
- botões customizados com quatro papéis visuais;
- await em worker thread com timeout;
- fechamento programático de qualquer thread;
- temas visuais completos com modelo de destaque do botão padrão;
- text provider plugável para localização;
- telemetria estruturada com sete eventos de ciclo de vida;
- segurança em destruição de formulário com supressão de callback;
- e uma facade de migração drop-in para chamadores existentes do `FMX.DialogService`.

---

## Leituras recomendadas

Para leitores que querem se aprofundar no framework FMX e em padrões assíncronos no Delphi, três referências valem destaque:

- **[Embarcadero DocWiki - `TDialogService.MessageDialog`](https://docwiki.embarcadero.com/Libraries/Florence/en/FMX.DialogService.TDialogService.MessageDialog)** - referência oficial do serviço de diálogos do FMX, incluindo o comportamento síncrono/assíncrono conforme o `PreferredMode` e a plataforma.
- **[Marco Cantù - *Object Pascal Handbook*](https://www.embarcadero.com/products/delphi/object-pascal-handbook)** - livro/eBook sobre Object Pascal moderno, incluindo métodos anônimos; a [página do autor](https://www.marcocantu.com/objectpascalhandbook/) também mantém referências para versões impressas e links da Amazon.
- **[Guia conceitual do SafeThread4D](https://github.com/eduardoparaujo/SafeThread4D/blob/main/docs/Guide_pt-BR.md)** - para um tratamento mais profundo de threading, `Synchronize`, `Queue` e padrões de coordenação com worker threads mencionados ao longo deste guia.

---

## Epílogo - Próximos passos

Se você chegou até aqui, tem uma fundação conceitual sólida sobre diálogos no FMX. Você sabe **por que** cada camada da história dos diálogos existe, do mais simples `ShowMessage` até um mecanismo completo de enfileiramento e observabilidade.

Próximos passos naturais:

1. **Clone o Dialog4D** e rode o demo distribuído. Cada uma das dez seções no demo corresponde a um conceito coberto neste guia.
2. **Leia o [README do projeto](../README.md)**, com a superfície da API e receitas de migração.
3. **Leia o [`Architecture.md`](Architecture.md)** se quiser entender o mecanismo por dentro - o registro, o host visual, o pipeline de fechamento e o tratamento de destruição de formulário.
4. **Leia o código-fonte** com calma. A biblioteca não é grande, e as peças mapeiam diretamente nos conceitos deste guia.

Se, em algum momento, você se pegar coordenando manualmente fila de diálogos, contornando mudanças de tema entre passos, ou desejando ter observabilidade de quais diálogos o usuário realmente viu, talvez seja hora de parar de reconstruir o mecanismo do zero em cada projeto.

---

*Este texto é um guia conceitual introdutório. Para uso prático e detalhes do mecanismo, consulte o [README.md](../README.md), as notas de arquitetura em [`Architecture.md`](Architecture.md), e os exemplos do projeto.*
