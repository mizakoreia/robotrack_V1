import type { AjudaText } from './ajuda'

// internationalization G3 — tradução EN (UK) da prosa da tela de Ajuda. Mesma forma
// e mesmas chaves de `ajuda.ts`; só o texto muda. Os ids das seções são estruturais
// (âncoras) e vivem na tela — não se traduzem.
//
// Glossário confirmado: Overview / My Tasks / Report / Help; Project/Cell/Robot/Task;
// Owner/Editor/Viewer; Comissionamento → Commissioning; Protocolo de Comissionamento
// → Commissioning Protocol; Avanço → Progress update / Registrar avanço → Log
// progress; métrica ponderada → Weighted progress; contagem crua → Task completion;
// anel de progresso → progress ring; chão de fábrica/galpão → shop floor.
export const ajudaTextEn: AjudaText = {
  pageTitle: 'Help',
  pageIntro: 'How RoboTrack works and how to use it, from start to finish. Tap a section to jump straight to it.',
  navLabel: 'Help sections',
  roles: {
    caption: 'What each role can do',
    actionHeader: 'Action',
    yes: 'Yes',
    no: 'no',
    badges: { owner: 'Owner', editor: 'Editor', viewer: 'Viewer' },
    actions: [
      'See everything',
      'Log progress',
      'Create and edit projects, cells, robots and tasks',
      'Assign people to tasks',
      'Invite people',
      'Delete cards and reset the workspace',
    ],
  },
  sections: [
    {
      id: 'o-que-e',
      title: 'What RoboTrack is',
      body: [
        {
          p: [
            'RoboTrack tracks the ',
            { b: 'commissioning of industrial robots' },
            ' — from the first bolt to the signed protocol. Every task on every robot gets a logged progress update, and that progress rolls up the hierarchy until it becomes the project’s overall picture.',
          ],
        },
        {
          p: [
            'It is built for the shop floor: readable from a distance, with large touch targets (you can use it wearing gloves) and working even ',
            { b: 'without internet' },
            '. The tool serves the work — logging progress takes seconds and the number you sign off at the end is trustworthy.',
          ],
        },
      ],
    },
    {
      id: 'estrutura',
      title: 'How the work is organised',
      body: [
        { p: ['The work is organised into five levels, from the largest to the smallest:'] },
        {
          steps: [
            [
              { b: 'Workspace' },
              ' — the space for your company/team. Each person owns their own and can be invited to collaborate on others.',
            ],
            [{ b: 'Project' }, ' — one commissioning delivery.'],
            [{ b: 'Cell' }, ' — a grouping of robots within the project (by line, station and so on).'],
            [{ b: 'Robot' }, ' — the equipment being commissioned. This is where you work day to day.'],
            [{ b: 'Task' }, ' — each item to complete on a robot (assembly, testing, adjustment…).'],
          ],
        },
        {
          p: [
            'Progress ',
            { b: 'rolls up from the bottom' },
            ': you log the update on the task, and the robot, the cell and the project recalculate on their own. You never fill in the project’s number by hand.',
          ],
        },
        {
          p: [
            'To avoid confusion, RoboTrack always shows ',
            { b: 'two named measures' },
            ', never a bare “progress”:',
          ],
        },
        {
          steps: [
            [
              { ref: 'weighted' },
              ' — the average task progress by weight (it is the progress ring). It shows how much of the work has actually been done.',
            ],
            [
              { ref: 'raw_count' },
              ' — how many tasks are complete divided by the total. It shows how many items have closed, unweighted.',
            ],
          ],
        },
      ],
    },
    {
      id: 'papeis',
      title: 'Roles and permissions',
      body: [
        { p: ['Everyone in a workspace has a role, and the role decides what they can do:'] },
        { rolesTable: true },
        {
          p: [
            'The server is always the one that authorises: the screen merely hides what you cannot do. If a button does not appear for you, it is because your role does not allow that action.',
          ],
        },
      ],
    },
    {
      id: 'navegar',
      title: 'Getting around the app',
      body: [
        {
          p: [
            'The sidebar has three fixed destinations. The rest (Settings, Help, account) lives in the account menu, in the bottom-left corner, and in this top bar.',
          ],
        },
        {
          steps: [
            [{ b: 'Overview' }, ' — your projects, each with the two progress measures. It is the way in.'],
            [{ b: 'Project → Cell' }, ' — go down the hierarchy by tapping the cards to reach the robots.'],
            [
              { b: 'Robot screen' },
              ' — the task table, where the work happens. Tasks sit in groups that open and close, with columns for status, progress, assignees and history.',
            ],
            [{ b: 'My Tasks' }, ' — only the tasks assigned to you, gathered from every robot.'],
            [{ b: 'Report' }, ' — the Commissioning Protocol, ready to print.'],
            [
              { b: 'Settings' },
              ' — people, base tasks, appearance, team/invitations and (for the owner) backup and reset.',
            ],
          ],
        },
      ],
    },
    {
      id: 'montar',
      title: 'Building the structure',
      body: [
        {
          p: [
            'The owner or an editor builds the hierarchy from the top down. On each screen there is a button to add the level below:',
          ],
        },
        {
          steps: [
            ['On the Overview, use ', { b: 'New Project' }, '.'],
            ['Inside the project, use ', { b: 'New cell' }, '.'],
            ['Inside the cell, use ', { b: 'Add robots' }, '.'],
          ],
        },
        {
          p: [
            'When you add robots, a two-step wizard lets you create ',
            { b: 'several at once' },
            ' — from 1 to 50 — by giving the quantity and the application. Each robot is born with the catalogue’s base tasks that apply to that application.',
          ],
        },
        {
          p: [
            'On the robot screen, the editor can ',
            { b: 'Add task' },
            ' individually, edit the existing ones and use ',
            { b: 'Sync base tasks' },
            ' to bring in the catalogue tasks still missing from that robot. The catalogue itself is managed in Settings → Base tasks.',
          ],
        },
      ],
    },
    {
      id: 'avanco',
      title: 'Logging progress on a task',
      body: [
        { p: ['It is the most common action day to day, and it takes seconds:'] },
        {
          steps: [
            ['On the robot screen, move the task’s progress control.'],
            [
              'Drag it to the real percentage. When you ',
              { b: 'let go' },
              ', the ',
              { b: 'Log progress' },
              ' window opens.',
            ],
            [
              'Below 100%, a ',
              { b: 'comment is required' },
              ' (say what was done or what is left). At 100%, the comment is optional.',
            ],
            [
              'Tap ',
              { b: 'Log progress' },
              '. The update joins the task’s history — which cannot be erased — and the progress of the robot, the cell and the project recalculates instantly.',
            ],
          ],
        },
        {
          p: [
            'The status follows the number: ',
            { b: 'Pending' },
            ' at 0%, ',
            { b: 'In Progress' },
            ' between 1% and 99% and ',
            { b: 'Complete' },
            ' at 100%. Changing the status also goes through the same progress window.',
          ],
        },
        {
          p: [
            'RoboTrack is honest about what it saved: it only says “saved” when it really saved. Without internet, the update waits in the queue and syncs when the network returns (see “Working offline”).',
          ],
        },
      ],
    },
    {
      id: 'responsaveis',
      title: 'Assigning people to tasks',
      body: [
        {
          p: [
            'On the robot screen, the ',
            { b: 'Assignees' },
            ' column defines who looks after each task. Assignment is ',
            { b: 'per person' },
            ': tick the people in the list — and, if someone is not there yet, add them right there. A task can have more than one assignee.',
          ],
        },
        {
          p: [
            'Whoever is assigned gets notified of that task’s updates and sees it in ',
            { b: 'My Tasks' },
            '. People can also be added and organised in Settings → People.',
          ],
        },
      ],
    },
    {
      id: 'convites',
      title: 'Inviting people',
      body: [
        {
          p: [
            'Invitations work by ',
            { b: 'code' },
            '. Whoever manages (owner or editor) uses ',
            { b: 'Invite person' },
            ' in the top bar, chooses the role (Editor or Viewer) and gets a short code, in the format ',
            { b: 'XXXX-XXXX' },
            '. Just pass that code to the person.',
          ],
        },
        { p: ['Whoever receives the code joins in one of two ways:'] },
        {
          steps: [
            ['Still without an account or signed out: on the sign-in screen, under ', { b: '“I have an invite code”' }, '.'],
            [
              'Already signed in to another workspace: in the account menu, under ',
              { ref: 'joinByCode' },
              '. The app switches to the new workspace and opens its Overview.',
            ],
          ],
        },
      ],
    },
    {
      id: 'notificacoes',
      title: 'Notifications',
      body: [
        {
          p: [
            'The ',
            { b: 'bell' },
            ' in the top bar shows how many notifications you have unread; tapping it opens the centre. By default, you get alerts for the tasks you are assigned to.',
          ],
        },
        {
          p: [
            'On top of that, in the header of each project, cell and robot there is a ',
            { b: 'preference' },
            ' bell, with three options:',
          ],
        },
        {
          steps: [
            [{ b: 'Follow' }, ' — get the updates for that level even without being assigned.'],
            [{ b: 'Mute' }, ' — do not get anything from that level.'],
            [{ b: 'Default' }, ' — the normal behaviour (you get what you are assigned to).'],
          ],
        },
        {
          p: [
            'The rule of ',
            { b: 'most specific wins' },
            ' applies: if you mute a cell, its robots go quiet — but if you follow a specific robot inside it, you start getting that robot again. The bell always shows the state in force and where it comes from.',
          ],
        },
        {
          p: [
            'The owner gets the updates for their whole workspace, to keep track without depending on being assigned.',
          ],
        },
      ],
    },
    {
      id: 'offline',
      title: 'Working offline',
      body: [
        {
          p: [
            'RoboTrack is an app that works ',
            { b: 'offline' },
            '. After opening it online at least once, it keeps working without a network:',
          ],
        },
        {
          steps: [
            ['Reads come from what has already been loaded (what you saw while online).'],
            [
              'Writes — updates, edits — go into a ',
              { b: 'queue' },
              ' and sync on their own when the network comes back.',
            ],
            ['The app warns you when it is offline and when there are pending items: you never think you saved without saving.'],
          ],
        },
        {
          p: [
            'The only exception: ',
            { b: 'signing in and creating an account need internet' },
            '. Once inside, the shop floor with no signal stops being a problem.',
          ],
        },
      ],
    },
    {
      id: 'excluir',
      title: 'Deleting items',
      body: [
        {
          p: ['Only the ', { b: 'Owner' }, ' deletes projects, cells, robots and tasks. The ways to delete:'],
        },
        {
          steps: [
            ['On a computer: via the ', { b: 'bin' }, ' icon on the card or the row.'],
            ['On a phone: ', { b: 'swipe the card to the left' }, ' to reveal the Delete button.'],
          ],
        },
        {
          p: [
            'Deleting always asks for ',
            { b: 'confirmation' },
            ' — nothing disappears with one tap. When you delete an item, whatever is below it is also archived (deleting a project archives its cells, robots and tasks). History and the audit trail are preserved.',
          ],
        },
      ],
    },
    {
      id: 'relatorio',
      title: 'Commissioning report',
      body: [
        {
          p: [
            'In ',
            { b: 'Report' },
            ', RoboTrack assembles the ',
            { b: 'Commissioning Protocol' },
            ' — the formal document signed at the end of the work. It consolidates the real progress of projects, cells and robots.',
          ],
        },
        {
          p: [
            'The document is in ',
            { b: 'A4' },
            ' format, ready to print (or save as PDF via the browser’s print option).',
          ],
        },
      ],
    },
  ],
}
