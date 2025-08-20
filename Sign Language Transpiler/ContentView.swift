import SwiftUI

struct ContentView: View {
    @StateObject var storage: StorageService
    @State private var signers: [Signer] = []
    @State private var showingNewSigner = false
    @State private var newName: String = ""
    @State private var pendingDelete: Signer? = nil
    @State private var showDeleteAlert = false

    var body: some View {
        NavigationStack {
            List {
                if signers.isEmpty {
                    Section {
                        VStack(spacing: 8) {
                            Text("No Signers yet")
                                .font(.headline)
                            Text("Tap **New Signer** to create a recording account. CSVs from the Watch will appear under each signer.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    }
                }

                ForEach(signers) { signer in
                    NavigationLink {
                        SignerDetailView(storage: storage, signer: signer)
                    } label: {
                        HStack {
                            Image(systemName: "person.fill.viewfinder")
                                .foregroundStyle(.blue)
                            VStack(alignment: .leading) {
                                Text(signer.name)
                                    .font(.headline)
                                Text(signer.id).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            pendingDelete = signer
                            showDeleteAlert = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle("Signers")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Seed Demo") { storage.seedDemoDataIfEmpty(); refresh() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        newName = ""
                        showingNewSigner = true
                    } label: {
                        Label("New Signer", systemImage: "plus")
                    }
                }
            }
            .onAppear(perform: refresh)
            .sheet(isPresented: $showingNewSigner) {
                NavigationStack {
                    Form {
                        Section(header: Text("Create New Signer")) {
                            TextField("Signer name", text: $newName)
                                .textInputAutocapitalization(.words)
                        }
                    }
                    .navigationTitle("New Signer")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showingNewSigner = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Create") { createSigner() }.disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                }
                .presentationDetents([.fraction(0.35), .medium])
            }
            .alert("Delete signer?", isPresented: $showDeleteAlert, presenting: pendingDelete) { signer in
                Button("Delete", role: .destructive) { deleteSigner(signer) }
                Button("Cancel", role: .cancel) { pendingDelete = nil }
            } message: { signer in
                Text("This will permanently delete all data for \(signer.name).")
            }
        }
    }

    private func refresh() {
        signers = storage.listSigners()
    }

    private func createSigner() {
        do {
            _ = try storage.createSigner(name: newName)
            showingNewSigner = false
            refresh()
        } catch {
            print("Failed to create signer: \(error)")
        }
    }

    private func deleteSigner(_ s: Signer) {
        do {
            try storage.deleteSigner(s)
            pendingDelete = nil
            refresh()
        } catch {
            print("Failed to delete signer: \(error)")
        }
    }
}
