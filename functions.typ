#let render_face(body) = {
    pdf.attach("abstract.typ", relationship: "source")
    pdf.attach("Appendix A.typ", relationship: "source")
    pdf.attach("Appendix B.typ", relationship: "source")
    pdf.attach("chapter1.typ", relationship: "source")
    pdf.attach("chapter2.typ", relationship: "source")
    pdf.attach("chapter3.typ", relationship: "source")
    pdf.attach("chapter4.typ", relationship: "source")
    pdf.attach("chapter5.typ", relationship: "source")
    pdf.attach("functions.typ", relationship: "source")
    pdf.attach("main.typ", relationship: "source")
    pdf.attach("refs.bib", relationship: "source")

    let tiny = 6pt
    let scriptsize = 8pt
    let footnotesize = 10pt
    let small = 11pt
    let normalsize = 11.96pt
    let large = 14.35pt
    let Large = 17.21pt
    let LARGE = 20.66pt
    let huge = 24.79pt
    let Huge = 25pt
    let spac = 1.5em

    set text(
        font: "sfrm1200",
        size: normalsize,
        lang: "en",
        top-edge: 0em,
        bottom-edge: 0em,
    )
    set par(
        spacing: spac,
        leading: spac,
    )

    show emph: set text(font: "sfti1200")
    show strong: set text(font: "sfbx1200")

    set list(indent: spac, spacing: 10.39mm)

    show list: it => {
        block(above: 10.89mm, below: 13.5mm)[#it]
    }
    set figure(
        gap: 2em,
    )
    set figure(numbering: (..nums) => [#counter(heading).display((
            ..heading_nums,
        ) => heading_nums.pos().at(0))\.#nums.pos().at(0)])

    show figure: set block(above: 5.98mm, below: 12.16mm)

    set page(
        width: 210mm,
        height: 297mm,
        margin: (top: 2.5cm, bottom: 2.5cm, left: 2.5cm, right: 2.5cm),
    )

    import "@preview/i-figured:0.2.4"
    show math.equation: i-figured.show-equation
    show heading.where(level: 2): it => block(
        below: 10.5mm,
        above: 15.95mm,
    )[#text(size: Large, font: "sfbx1728")[#it]]
    show heading.where(level: 3): it => block(
        below: 7.04mm,
        above: 11.98mm,
    )[#text(size: large, font: "sfbx1440")[#it]]

    set align(center)
    text(size: LARGE, font: "sfbx2074")[
        #par(spacing: 2.5cm)[Thesis]
        #par(
            spacing: 2.5cm,
        )[Vehicle-in-the-Loop simulation using CARLA simulator]
        #block(below: 4cm)[#par(leading: normalsize * 1.5)[#text(
                size: normalsize,
                font: "sfti1200",
            )[Author:]\ #text(size: large, font: "sfbx1440")[Kamolov Makhmud]]]
    ]

    block(below: 0.5cm)[
        #box(width: 7cm)[
            #image("image/BMElogo.png")
        ]
    ]

    block(below: 2.5cm)[#text(font: "sfrm1200")[
            Budapest University of Technology and Economics\ Department of Control for Transportation and Vehicle Systems]
    ]

    [#text(font: "sfti1200")[Supervisor:]

        #text(font: "sfbx1200")[Szőke László]]

    let date = datetime.today()

    place(bottom + center, dy: -5mm)[#text(font: "sfrm1200")[Thesis:] \ #text(
            size: large,
            font: "sfrm1440",
        )[#date.display("[month repr:long] [day], [year]")]]
    pagebreak() //      1st page finish

    set table(
        stroke: (_, y) => (
            top: if y == 0 { 0.7pt } else if y == 1 { 0.4pt } else { 0pt },
            bottom: 0.4pt,
        ),
        align: (x, y) => (
            if x > 0 { center } else { left }
        ),
    )

    set align(left)
    counter(page).update(1)
    set page(numbering: "1")
    set par(leading: spac)

    show raw: set text(size: normalsize, font: "sftt1200", hyphenate: true)

    show outline.entry.where(
        level: 1,
    ): it => link(it.element.location(), block(
        above: 1.8em - normalsize,
    )[#strong[#it.prefix() #it.body()]])

    block(below: 2.25cm)[#text(size: huge, font: "sfbx2488")[Contents]]

    /////////////////////////////////////////////
    set text(
        font: "sfrm1200",
        size: normalsize,
        lang: "en",
        top-edge: "ascender",
        bottom-edge: "descender",
    )
    set par(
        spacing: spac - normalsize,
        leading: spac - normalsize,
    )
    outline(title: none, depth: 2)
    set text(
        font: "sfrm1200",
        size: normalsize,
        lang: "en",
        top-edge: 0em,
        bottom-edge: 0em,
    )
    set par(
        spacing: spac,
        leading: spac,
    )
    /////////////////////////////////////////////

    pagebreak()

    set par(first-line-indent: spac, justify: true)

    set heading(numbering: "1.1")
    show heading.where(
        level: 1,
    ): it => {
        counter(figure.where(kind: image)).update(0)
        pagebreak()
        block(width: 100%, below: 21.45mm)[
            #set text(huge, font: "sfbx2488")
            #set par(leading: 2.3em, spacing: 2.3em)
            Chapter #counter(heading).display("1")
            #set par(first-line-indent: 0em)
            #it.body
        ]
    }

    let style-number(number) = text(gray)[#number]
    show raw.where(block: true): it => grid(
        columns: 2,
        align: (right, left),
        gutter: 1.5em,
        ..it
            .lines
            .enumerate()
            .map(((i, line)) => (style-number(i + 1), line))
            .flatten()
    )

    body // body bu yerda turibdi  ///////////////////////////////////////

    show outline.entry.where(
        level: 1,
    ): it => link(it.element.location(), block(
        above: 1.8em - normalsize,
    )[#it.prefix() #it.inner()])

    pagebreak()
    block(width: 100%, below: 21.45mm)[
        #set text(huge, font: "sfbx2488")
        #set par(leading: 2.3em, spacing: 2.3em)
        #set par(first-line-indent: 0em)
        Bibliography
    ]
    bibliography("refs.bib", title: none)

    ///////////////////////////////////////////////////////
    pagebreak()
    block(below: 2.25cm)[#text(size: huge, font: "sfbx2488")[List of Figures]]
    set text(
        font: "sfrm1200",
        size: normalsize,
        lang: "en",
        top-edge: "ascender",
        bottom-edge: "descender",
    )
    set par(
        spacing: spac - normalsize,
        leading: spac - normalsize,
    )
    outline(title: none, target: figure.where(kind: image))
    set text(
        font: "sfrm1200",
        size: normalsize,
        lang: "en",
        top-edge: 0em,
        bottom-edge: 0em,
    )
    set par(
        spacing: spac,
        leading: spac,
    )
    ///////////////////////////////////////////////////////

    ///////////////////////////////////////////////////////
    pagebreak()
    block(below: 2.25cm)[#text(size: huge, font: "sfbx2488")[List of Tables]]
    set text(
        font: "sfrm1200",
        size: normalsize,
        lang: "en",
        top-edge: "ascender",
        bottom-edge: "descender",
    )
    set par(
        spacing: spac - normalsize,
        leading: spac - normalsize,
    )
    outline(title: none, target: figure.where(kind: table))
    set text(
        font: "sfrm1200",
        size: normalsize,
        lang: "en",
        top-edge: 0em,
        bottom-edge: 0em,
    )
    set par(
        spacing: spac,
        leading: spac,
    )
    ///////////////////////////////////////////////////////

    // APPENDIXES

    set heading(numbering: "A")
    counter(heading).update(0)
    show heading.where(
        level: 1,
    ): it => {
        counter(figure.where(kind: image)).update(0)
        pagebreak()
        block(width: 100%, below: 21.45mm)[
            #set text(huge, font: "sfbx2488")
            #set par(leading: 2.3em, spacing: 2.3em)
            Appendix #counter(heading).display("A")
            #set par(first-line-indent: 0em)
            #it.body
        ]
    }

    include "Appendix A.typ"
    include "Appendix B.typ"
}
